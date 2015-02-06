require 'redis_exp_lock'
require 'redis'
require 'yaml'

describe RedisExpLock do

  let(:redis_config) { YAML.load_file(File.join(File.dirname(__FILE__), 'redis.yml')) }
  let(:redis) { Redis.new(redis_config) }
  let(:lock) { RedisExpLock.new('test_key', :redis => redis) }
  let(:other_lock) { RedisExpLock.new('test_key', :redis => redis) }
  let(:fast_expiring_lock) { RedisExpLock.new('test_key', :redis => redis, :expiry => 0.1) }
  let(:non_expiring_lock) { RedisExpLock.new('test_key', :redis => redis, :expiry => nil) }
  let(:retry_lock) { RedisExpLock.new('test_key', :redis => redis, :retries => 10) }

  before :each do
    redis.flushdb
  end

  describe '#locked?' do

    it 'should respond false if not locked' do
      expect(lock.locked?).to eql(false)
    end

    it 'should respond true if locked' do
      lock.lock
      expect(lock.locked?).to eql(true)
    end

    it 'should respond false after unlocking' do
      lock.lock
      lock.unlock
      expect(lock.locked?).to eql(false)
    end

    it 'should respond correctly in and out of a synchronize block' do
      lock.synchronize do
        expect(lock.locked?).to eql(true)
      end
      expect(lock.locked?).to eql(false)
    end

  end # describe '#locked?'

  describe '#key_locked?' do

    it 'should respond false if no clients have locked the key' do
      expect(lock.key_locked?).to eql(false)
    end

    it 'should respond true if at least one client has locked the key' do
      lock.lock
      expect(lock.key_locked?).to eql(true)
      expect(other_lock.key_locked?).to eql(true)
    end

  end

  describe '#key_owned?' do

    it 'should respond false if no clients anywhere have acquired the lock' do
      expect(lock.key_owned?).to eql(false)
    end

    it 'should respond true if the client has acquired the lock' do
      lock.lock
      expect(lock.key_owned?).to eql(true)
      expect(other_lock.key_owned?).to eql(false)
    end

  end

  describe '#try_lock' do

    it 'should return false if another client has acquired the lock' do
      lock.lock
      expect(other_lock.try_lock).to eql(false)
    end

    it 'should return true if no other client has acquired the lock' do
      expect(lock.try_lock).to eql(true)

      # Some side conditions, for good measure
      expect(lock.locked?).to eql(true)
      expect(lock.key_locked?).to eql(true)
      expect(lock.key_owned?).to eql(true)
    end

    it 'should raise an AlreadyAcquiredLockError if the client has already acquired the lock' do
      lock.try_lock
      expect { lock.try_lock }.to raise_error(RedisExpLock::AlreadyAcquiredLockError)
    end

    it 'should set an expiring lock if the :expiry option was set' do
      fast_expiring_lock.try_lock
      expect(fast_expiring_lock.key_owned?).to eql(true)
      sleep 0.2
      expect(fast_expiring_lock.key_owned?).to eql(false)
    end

    it 'should set a non-expiring lock if the :expiry option is nil' do
      non_expiring_lock.try_lock
      5.times do
        sleep 0.1
        expect(non_expiring_lock.key_owned?).to eql(true)
      end
    end

  end

  describe '#lock' do

    it 'should set the client in a locked state if the lock was successful' do
      lock.lock
      expect(lock.locked?).to eql(true)
    end

    it 'should raise an TooManyLockAttemptsError if the client cannot acquire the lock' do
      lock.lock
      expect { other_lock.lock }.to raise_error(RedisExpLock::TooManyLockAttemptsError)
    end

    it 'should attempt to re-acquire the lock if is not initially available' do
      # Acquire the lock with a different client, and release it within the total
      # retry period.
      other_lock.lock
      Thread.new do
        sleep 0.015
        other_lock.unlock
      end

      attempts = 0
      expect { attempts = retry_lock.lock }.not_to raise_error
      expect(attempts).to be > 0
    end

  end

  describe '#unlock' do

    it 'should return true if the client owned the lock' do
      lock.lock
      expect(lock.unlock).to eql(true)
    end

    it 'should return false if the client never acquired the lock' do
      expect(lock.unlock).to eql(false)
    end

    it 'should return false if the client acquired the lock, but the lock expired before unlocking' do
      fast_expiring_lock.lock
      sleep 0.2
      expect(fast_expiring_lock.unlock).to eql(false)
    end

    it 'should set the client to an unlocked state' do
      lock.lock
      expect(lock.locked?).to eql(true)
      expect(lock.key_locked?).to eql(true)
      expect(lock.key_owned?).to eql(true)

      lock.unlock
      expect(lock.locked?).to eql(false)
      expect(lock.key_locked?).to eql(false)
      expect(lock.key_owned?).to eql(false)
    end

    it 'should allow other clients to acquire the lock' do
      lock.lock
      expect(other_lock.try_lock).to eql(false)

      lock.unlock
      expect(other_lock.try_lock).to eql(true)
    end

    it 'should not interfere with other clients if the lock acquisition expires' do
      fast_expiring_lock.lock
      sleep 0.2

      expect(fast_expiring_lock.locked?).to eql(true)
      expect(fast_expiring_lock.key_owned?).to eql(false)

      # After sleeping, the lock should have expired remotely. New acquisition
      # attempts should succeed.
      expect(other_lock.try_lock).to eql(true)

      fast_expiring_lock.unlock

      expect(fast_expiring_lock.locked?).to eql(false)
      expect(other_lock.key_owned?).to eql(true)
    end

  end

  describe '#synchronize' do

    it 'should prevent other clients from acquiring the lock in the critical section' do
      lock.synchronize do
        expect(other_lock.try_lock).to eql(false)
      end
    end

    it 'should allow other clients to aqcuire the lock outside of the critical section' do
      lock.synchronize do
        # do nothing
      end
      expect(other_lock.try_lock).to eql(true)
    end

    it 'should not interfere with other clients if the acquired lock expires' do
      fast_expiring_lock.synchronize do
        sleep 0.2
        expect(other_lock.try_lock).to eql(true)
      end
    end

  end

end # describe RedisExpLock