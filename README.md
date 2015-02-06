# redis_exp_lock

A Ruby library providing distributed mutual exclusion using Redis. If you want to prevent multiple network nodes on from accessing a shared resource at the same time, and don't want to roll out a Zookeeper cluster (nobody's judging), this is for you. By default, locks provided by this library use an  expiration time, to prevent irrecoverable locks in case the client fails.

## Requirements

Redis 2.6.12 or higher, because:

- This library uses Redis's Lua functionality in order to eliminate certain race conditions on lock release. Lock expiration is handled by the Redis server itself, eliminating the need for precise time synchronization between your application hosts.
- This library uses the `SET` command with the `PX` and `NX` optional parameters. It's possible to emulate this functionality using Lua, but the current library omits this for brevity.

## Usage example

```ruby
require 'redis'
requie 'redis_exp_lock'

redis = Redis.new

# Create a new lock client
lock = RedisExpLock.new('lock_key', :redis => redis)

# Use the client to provide mutual exclusion.
lock.synchronize do
  # Put critical section code here.
end
```

## Installation

Add to your Gemfile:

```ruby
gem 'redis_exp_lock'
```

## API

### ::initialize(lock_key, opts)

Creates a new lock client. The constructor takes two parameters, a lock key and and a hash of configuration options.

The **lock key** key identifies a resource to be locked. Clients with the same lock key can only acquire the lock one at a time.

The **options hash** takes the following options:

##### :redis

(required) An instance of a Redis client that obeys the [redis-rb](https://github.com/redis/redis-rb) interface.

##### :expiry

The lifetime of the lock, in seconds. A lock's lifetime begins counting down as soon as the Redis key corresponding to the lock is successfully set. Set this to `nil` if you want a non-expiring lock, which is not recommended. Defaults to 60 seconds.

##### :retries

In the event that the lock has been acquired by another client, the current client can automatically attempt to re-acquire the lock, up to a configurable number of attempts. Defaults to zero (no automatic retries).

##### :interval

The amount of time in seconds that the client will wait before attempting to re-acquire the lock. Defaults to 0.01 (ten milliseconds).

### #locked?

Without calling into Redis, returns whether the local lock is in a lock state, i.e., `lock` has been called without a corresponding `unlock`.

### #key_locked?

Calls remotely to Redis to determine if the lock key has been locked by *any* client.

### #key_owned?

Calls remotely to Redis to determine if the client currently owns the lock.

### #try_lock

Attempts to obtain the lock and returns immediately. Returns `true` if the lock was successfully acquired, otherwise returns `false`.

- Raises `RedisExpLock::AlreadyAcquiredLockError` if client's lock state has not yet been cleared, i.e., if `#lock` was previously called without a corresponding `#unlock`.

### #lock

Attempts to grab the lock, and waits if it isn’t available. Returns the number of attempts required to acquire the lock.

- Raises `RedisExpLock::AlreadyAcquiredLockError` if client's lock state has not yet been cleared, i.e., if `#lock` was previously called without a corresponding `#unlock`.
- Raises `RedisExpLock::TooManyLockAttemptsError` if the max number of retries is exceed when attempting to acquire the lock.

### #unlock

Releases the lock. Returns `true` if the lock was successfully released. Returns `false` if the client never acquired the lock, or the lock expired before the unlock.

### #synchronize(&block)

Obtains a lock, runs the supplied block, and releases the lock when the block completes. Yields the number of attempts required to acquire the lock.

- Raises `RedisExpLock::AlreadyAcquiredLockError` if client's lock state has not yet been cleared, i.e., if `#lock` was previously called without a corresponding `#unlock`.
- Raises `RedisExpLock::TooManyLockAttemptsError` if the max number of retries is exceed when attempting to acquire the lock.

## Algorithm

### Lock acquisition

Locks are acquired by setting a Redis key with a UUID generated immediately prior to the lock attempt.

Since the Redis server manages the lifetime, there is no need for any client-side logic that deals with lock expiration, and thus no need to ensure that clients are time-synchronized.

### Lock release

Locks are released by deleting the Redis key, **only if** the key's value matches the UUID generated during a successful lock attempt. A Lua script provides the following atomic sequence:

1. `GET` the value of the key.
2. If the value of the key is the same as the UUID, then use `DEL` to remove the key.

Without using a Lua script to ensure atomicity, it's possible to encounter subtle race conditions, in which another client acquires the lock between the two steps above.

### Caveats

Lock clients in this library rely on prompt responses from the Redis server. Under aberrant network conditions, there are some edge cases that may cause your application to get out of whack. For example:

1. Lock acquisition requests may be received by the Redis server, but the response could fail to reach the client (e.g., in a socket timeout on the client side). In other words, it's possible that the Redis server thinks the lock has been acquired, but the local client doesn't. If this is a serious concern, be sure to set an expiry value so that the lock can automatically be released by the Redis server.
2. For expiring locks: it may take a while for the Redis server to respond to a lock acquisition request. This may result in situations where your critical section may not have the full lifetime of the lock to complete. In extreme cases, it's possible for the lock to have already expired on the server by the time the client recognizes its acquisition. If this is a serious concern, consider wrapping the lock acquisition with a timer to make sure you actually have enough time to proceed with your critical section.