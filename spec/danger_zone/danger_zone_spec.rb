require "danger_zone"
require 'fileutils'
###
# NOTE most of these specs were ported from those in racks memcache
# session store.
# 
# As this file is substantially a port of the rack memcache session
# store the copyright's here belong to Christian Neukirchen
# <purl.org/net/chneukirchen> of the rack project.  Many thanks!
###

describe DangerZone::SessionStore do

  let(:session_dir) { File.join('/','tmp','danger_zone_session_store_for_specs') }
  
  after :all do
    FileUtils.rm_rf session_dir
  end
  
  session_key = DangerZone::SessionStore::DEFAULT_OPTIONS[:key]

  session_match = /#{session_key}=([0-9a-fA-F]+);/
  incrementor = lambda do |env|
    env["rack.session"]["counter"] ||= 0
    env["rack.session"]["counter"] += 1
    Rack::Response.new(env["rack.session"].inspect).to_a
  end
  drop_session = proc do |env|
    env['rack.session.options'][:drop] = true
    incrementor.call(env)
  end
  renew_session = proc do |env|
    env['rack.session.options'][:renew] = true
    incrementor.call(env)
  end
  defer_session = proc do |env|
    env['rack.session.options'][:defer] = true
    incrementor.call(env)
  end
  skip_session = proc do |env|
    env['rack.session.options'][:skip] = true
    incrementor.call(env)
  end

  context do
    # this context houses specs which use an incrementor app
    let(:pool) {DangerZone::SessionStore.new incrementor, :session_store_path => session_dir}
    
    context 'storage path' do
      
      it 'is created if it doesnt exist already' do
        File.exist?(session_dir).should be_true
      end
      
      it 'stores the sessions' do
        pool.stub(:generate_sid).and_return 'stubbed-session-id'
        res = Rack::MockRequest.new(pool).get("/")
        File.exist?(File.join(session_dir,"stubbed-session-id.dzsession")).should be_true
      end
    end
    
    it "creates a new cookie" do
      res = Rack::MockRequest.new(pool).get("/")
      res["Set-Cookie"].should match "#{session_key}="
      res.body.should == '{"counter"=>1}'
    end

    it "determines session from a cookie" do
      req = Rack::MockRequest.new(pool)
      res = req.get("/")
      cookie = res["Set-Cookie"]
      req.get("/", "HTTP_COOKIE" => cookie).
        body.should == '{"counter"=>2}'
      req.get("/", "HTTP_COOKIE" => cookie).
        body.should == '{"counter"=>3}'
    end  

    it "determines session only from a cookie by default" do
      req = Rack::MockRequest.new(pool)
      res = req.get("/")
      sid = res["Set-Cookie"][session_match, 1]
      req.get("/?rack.session=#{sid}").
        body.should == '{"counter"=>1}'
      req.get("/?rack.session=#{sid}").
        body.should == '{"counter"=>1}'
    end

    it "survives nonexistant cookies" do
      bad_cookie = "rack.session=blarghfasel"
      res = Rack::MockRequest.new(pool).
        get("/", "HTTP_COOKIE" => bad_cookie)
      res.body.should == '{"counter"=>1}'
      cookie = res["Set-Cookie"][session_match]
      cookie.should_not match(/#{bad_cookie}/)
    end

    it "does not send the same session id if it did not change" do
      req = Rack::MockRequest.new(pool)

      res0 = req.get("/")
      cookie = res0["Set-Cookie"][session_match]
      res0.body.should == '{"counter"=>1}'

      res1 = req.get("/", "HTTP_COOKIE" => cookie)
      res1["Set-Cookie"].should be_nil
      res1.body.should == '{"counter"=>2}'

      res2 = req.get("/", "HTTP_COOKIE" => cookie)
      res2["Set-Cookie"].should be_nil
      res2.body.should == '{"counter"=>3}'
    end

    it "deletes cookies with :drop option" do
      req = Rack::MockRequest.new(pool)
      drop = Rack::Utils::Context.new(pool, drop_session)
      dreq = Rack::MockRequest.new(drop)

      res1 = req.get("/")
      session = (cookie = res1["Set-Cookie"])[session_match]
      res1.body.should == '{"counter"=>1}'

      res2 = dreq.get("/", "HTTP_COOKIE" => cookie)
      res2["Set-Cookie"].should be_nil
      res2.body.should == '{"counter"=>2}'

      res3 = req.get("/", "HTTP_COOKIE" => cookie)
      res3["Set-Cookie"][session_match].should_not == session
      res3.body.should == '{"counter"=>1}'
    end

    it "provides new session id with :renew option" do
      pending 'TODO add renewal support (Currently optional and implementation dependant)'

      req = Rack::MockRequest.new(pool)
      renew = Rack::Utils::Context.new(pool, renew_session)
      rreq = Rack::MockRequest.new(renew)

      res1 = req.get("/")
      session = (cookie = res1["Set-Cookie"])[session_match]
      res1.body.should == '{"counter"=>1}'

      res2 = rreq.get("/", "HTTP_COOKIE" => cookie)
      new_cookie = res2["Set-Cookie"]
      new_session = new_cookie[session_match]
      new_session.should_not == session
      res2.body.should == '{"counter"=>2}'

      res3 = req.get("/", "HTTP_COOKIE" => new_cookie)
      res3.body.should == '{"counter"=>3}'

      # Old cookie was deleted
      res4 = req.get("/", "HTTP_COOKIE" => cookie)
      res4.body.should == '{"counter"=>1}'
    end

    it "omits cookie with :defer option but still updates the state" do
      count = Rack::Utils::Context.new(pool, incrementor)
      defer = Rack::Utils::Context.new(pool, defer_session)
      dreq = Rack::MockRequest.new(defer)
      creq = Rack::MockRequest.new(count)

      res0 = dreq.get("/")
      res0["Set-Cookie"].should == nil
      res0.body.should == '{"counter"=>1}'

      res0 = creq.get("/")
      res1 = dreq.get("/", "HTTP_COOKIE" => res0["Set-Cookie"])
      res1.body.should == '{"counter"=>2}'
      res2 = dreq.get("/", "HTTP_COOKIE" => res0["Set-Cookie"])
      res2.body.should == '{"counter"=>3}'
    end

    it "omits cookie and state update with :skip option" do
      count = Rack::Utils::Context.new(pool, incrementor)
      skip = Rack::Utils::Context.new(pool, skip_session)
      sreq = Rack::MockRequest.new(skip)
      creq = Rack::MockRequest.new(count)

      res0 = sreq.get("/")
      res0["Set-Cookie"].should == nil
      res0.body.should == '{"counter"=>1}'

      res0 = creq.get("/")
      res1 = sreq.get("/", "HTTP_COOKIE" => res0["Set-Cookie"])
      res1.body.should == '{"counter"=>2}'
      res2 = sreq.get("/", "HTTP_COOKIE" => res0["Set-Cookie"])
      res2.body.should == '{"counter"=>2}'
    end

  end

  context do
    # Context contains pools configured with miscellaneous options
    it "determines session from params" do
      pool = DangerZone::SessionStore.new(incrementor, :cookie_only => false, :session_store_path => session_dir)
      req = Rack::MockRequest.new(pool)
      res = req.get("/")
      sid = res["Set-Cookie"][session_match, 1]
      req.get("/?rack.session=#{sid}").
        body.should == '{"counter"=>2}'
      req.get("/?rack.session=#{sid}").
        body.should == '{"counter"=>3}'
    end
    
    it "updates deep hashes correctly" do

      hash_check = proc do |env|
        session = env['rack.session']
        unless session.include? 'test'
          session.update :a => :b, :c => { :d => :e },
                         :f => { :g => { :h => :i} }, 'test' => true
        else
          session[:f][:g][:h] = :j
        end
        [200, {}, [session.inspect]]
      end
      pool = DangerZone::SessionStore.new(hash_check, :session_store_path => session_dir)
      req = Rack::MockRequest.new(pool)

      res0 = req.get("/")
      session_id = (cookie = res0["Set-Cookie"])[session_match, 1]

      ses0 = pool.get_session({}, session_id)

      req.get("/", "HTTP_COOKIE" => cookie)
      ses1 = pool.get_session({}, session_id)

      ses1.should_not == ses0
    end

    # # anyone know how to do this better?
    it "cleanly merges sessions when multithreaded" do
      unless $DEBUG
        1.should == 1 # fake assertion to appease the mighty bacon
        next
      end
      warn 'Running multithread test for DangerZone::SessionStore'
      pool = DangerZone::SessionStore.new(incrementor, :session_store_path => session_dir)
      req = Rack::MockRequest.new(pool)

      res = req.get('/')
      res.body.should == '{"counter"=>1}'
      cookie = res["Set-Cookie"]
      session_id = cookie[session_match, 1]

      delta_incrementor = lambda do |env|
        # emulate disconjoinment of threading
        env['rack.session'] = env['rack.session'].dup
        Thread.stop
        env['rack.session'][(Time.now.usec*rand).to_i] = true
        incrementor.call(env)
      end
      tses = Rack::Utils::Context.new pool, delta_incrementor
      treq = Rack::MockRequest.new(tses)
      tnum = rand(7).to_i+5
      r = Array.new(tnum) do
        Thread.new(treq) do |run|
          run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
        end
      end.reverse.map{|t| t.run.join.value }
      r.each do |request|
        request['Set-Cookie'].should == cookie
        request.body.should.include '"counter"=>2'
      end

      session = pool.pool.get(session_id)
      session.size.should == tnum+1 # counter
      session['counter'].should == 2 # meeeh

      tnum = rand(7).to_i+5
      r = Array.new(tnum) do |i|
        app = Rack::Utils::Context.new pool, time_delta
        req = Rack::MockRequest.new app
        Thread.new(req) do |run|
          run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
        end
      end.reverse.map{|t| t.run.join.value }
      r.each do |request|
        request['Set-Cookie'].should == cookie
        request.body.should.include '"counter"=>3'
      end

      session = pool.pool.get(session_id)
      session.size.should.be tnum+1
      session['counter'].should.be 3

      drop_counter = proc do |env|
        env['rack.session'].delete 'counter'
        env['rack.session']['foo'] = 'bar'
        [200, {'Content-Type'=>'text/plain'}, env['rack.session'].inspect]
      end
      tses = Rack::Utils::Context.new pool, drop_counter
      treq = Rack::MockRequest.new(tses)
      tnum = rand(7).to_i+5
      r = Array.new(tnum) do
        Thread.new(treq) do |run|
          run.get('/', "HTTP_COOKIE" => cookie, 'rack.multithread' => true)
        end
      end.reverse.map{|t| t.run.join.value }
      r.each do |request|
        request['Set-Cookie'].should == cookie
        request.body.should.include '"foo"=>"bar"'
      end

      session = pool.pool.get(session_id)
      session.size.should.be r.size+1
      session['counter'].should.be.nil?
      session['foo'].should == 'bar'
    end
  end  
end
