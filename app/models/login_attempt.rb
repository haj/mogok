
class LoginAttempt < ActiveRecord::Base

  def blocked?
    self.blocked_until && self.blocked_until > Time.now
  end

  def increment_or_block(max_attempts, block_time_hours)
    if self.attempts_count < (max_attempts - 1)
      self.attempts_count += 1
    else
      self.blocked_until = block_time_hours.hours.from_now
      self.attempts_count = 0
      register_login_block self.ip
    end
    save
  end

  def self.delete_all_by_ip(ip)
    delete_all ['ip = ?', ip]
  end

  def self.fetch(ip)
    find_by_ip(ip) || create(:ip => ip, :attempts_count => 0)
  end

  private

  def register_login_block(ip)
    b = LoginBlock.find_by_ip ip
    unless b
      LoginBlock.create :ip => ip, :blocks_count => 1
    else
      b.increment! :blocks_count
    end
  end
end