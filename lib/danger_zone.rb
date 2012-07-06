require "danger_zone/version"
require 'rack/session/abstract/id'
require 'rack/mock'
require 'yaml'

module DangerZone
  class SessionStore < Rack::Session::Abstract::ID

    DEFAULT_OPTIONS = Rack::Session::Abstract::ID::DEFAULT_OPTIONS.merge :session_store_path => File.join('/tmp','danger-zone-sessions')
    FILE_EXTENSION = 'dzsession'


    def initialize(app, options={})
      super
      @session_store_path = options[:session_store_path] || DEFAULT_OPTIONS[:session_store_path]
      Dir.mkdir @session_store_path unless File.exist? @session_store_path
    end

    # Override incase the superclass is running in an environment
    # without SecureRandom.  In this case we need to guarantee the
    # uniqueness of keys ourselves.
    def generate_sid
      loop do
        sid = super
        break sid unless File.exist?(session_file(sid))
      end
    end    
    
    def create_session 
      sid, session = generate_sid, {}
      with_write_lock sid do |f|
        f.puts session.to_yaml
      end
      [sid,session]
    end
    
    def get_session(env, sid)
      ret = [nil, {}]
      if sid == nil
        ret = create_session
      else
        begin 
          with_read_lock(sid) do |f|
            ret = [sid, YAML.load(f)]
          end
        rescue Errno::ENOENT
          ret = create_session
        end
      end
      ret
    end

    def set_session(env, session_id, new_session, options)
      with_write_lock(session_id) do |f|
        f.puts new_session.to_yaml
      end
      session_id
    end

    def destroy_session(env, session_id, options)
      File.unlink session_file(session_id)
      generate_sid unless options[:drop]
    end

    private

    def session_file session_id
      File.join @session_store_path, "#{session_id}.#{FILE_EXTENSION}"
    end
    
    def with_read_lock session_id
      ret = nil
      File.open(session_file(session_id), 'r') do |f|
        f.flock(File::LOCK_SH)
        ret = yield f
      end
      ret
    end

    def with_write_lock session_id
      File.open(session_file(session_id), File::RDWR|File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        f.rewind
        yield f
        f.flush
        f.truncate(f.pos)
      end
    end
  end
end
