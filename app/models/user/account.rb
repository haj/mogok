
class User

  # account concern

  attr_reader :password
  attr_accessor :password_confirmation  

  def self.authenticate(username, password)
    u = self.find_by_username username
    if u && u.encrypted_password == CryptUtils.encrypt_password(password, u.salt)
      return u
    end
    nil
  end

  def self.make_invite_code
    CryptUtils.md5_token '', 20
  end

  def self.make_password_recovery_code
    CryptUtils.md5_token
  end

  def log_in(keep_logged_in, max_inactivity_threshold)
    self.last_login_at = Time.now
    reset_token
    self.token_expires_at = keep_logged_in ? 30.days.from_now : max_inactivity_threshold
    save
  end

  def password=(password)    
    unless password.blank?
      self.salt = CryptUtils.md5_token object_id
      self.encrypted_password = CryptUtils.encrypt_password password, self.salt
    end
    @password = password
  end

  def change_password(password, confirmation)
    self.password = password
    self.password_confirmation = confirmation
    save
  end

  def slide_token_expiration(limit_period)
    if self.token_expires_at <= limit_period.minutes.from_now
      self.token_expires_at = limit_period.minutes.from_now
    end
  end

  def reset_token
    self.token = CryptUtils.md5_token self.id, 20
  end

  def create_password_recovery
    code = User.make_password_recovery_code
    PasswordRecovery.delete_all_by_user self
    PasswordRecovery.create :created_at => Time.now, :code => code, :user => self
    code
  end

  def save_with_invite(code, invite_required)
    # note: new user may have an invite even if it is not required
    i = Invitation.find_by_code code
    unless i
      if invite_required
        add_error :invite_code, 'invalid'
        return false
      end
    else
      self.inviter_id = i.user_id
      logger.debug ":-) inviter id: #{self.inviter_id}"
    end
    if save
      logger.debug ":-) user created. id: #{self.id}"
      i.destroy if i
      return true
    end
    false
  end
end












