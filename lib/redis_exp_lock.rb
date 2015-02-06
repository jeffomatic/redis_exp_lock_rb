require 'shavaluator'

class RedisExpLock

	# Errors
	class TooManyLockAttemptsError < RuntimeError; end
	class AlreadyAcquiredLockError < RuntimeError; end

	LUA = {
  	# Deletes keys if they equal the given values
		:delequal => """
	    local deleted = 0
	    if redis.call('GET', KEYS[1]) == ARGV[1] then
	      return redis.call('DEL', KEYS[1])
	    end
	    return 0
		""",
	}

	attr_reader :redis, :lock_key, :lock_uuid, :expiry, :retries, :retry_interval

	def initialize(lock_key, opts)
		defaults = {
			:expiry => nil, # in seconds
			:retries => 0,
			:retry_interval => 0.01, # in seconds
		}
		opts = {}.merge(defaults).merge(opts)

		@lock_key = lock_key.to_s
		raise ArgumentError.new('Invalid lock key') unless @lock_key.size > 0
		@lock_uuid = nil

		@redis = opts[:redis]
		@shavaluator = Shavaluator.new(:redis => @redis)
		@shavaluator.add(LUA)

		@expiry = opts[:expiry]
		@retries = opts[:retries]
		@retry_interval = opts[:retry_interval]
	end

	def locked?
		!@lock_uuid.nil?
	end

	def key_locked?
		@redis.exists(@lock_key)
	end

	def key_owned?
		!@lock_uuid.nil? && @lock_uuid == @redis.get(@lock_key)
	end

	# Attempt to acquire the lock, returning true if the lock was succesfully
	# acquired, and false if not.
	def try_lock
		raise AlreadyAcquiredLockError if locked?

		uuid = SecureRandom.uuid
		set_opts = {
			:nx => true
		}
    set_opts[:px] = Integer(@expiry * 1000) if @expiry

    if @redis.set(@lock_key, uuid, set_opts)
    	@lock_uuid = uuid
    	true
    else
    	false
    end
	end

	def lock
		attempts = 0
		while attempts <= @retries
			attempts += 1
			return attempts if try_lock
			sleep @retry_interval
		end
		raise TooManyLockAttemptsError
	end

	def unlock
		return false unless locked?
		was_locked = @shavaluator.exec(:delequal, :keys => [@lock_key], :argv => [@lock_uuid]) == 1
		@lock_uuid = nil
		was_locked
	end

	def synchronize(&crit_sec)
		attempts = lock
		crit_sec.call attempts
		unlock
	end

end