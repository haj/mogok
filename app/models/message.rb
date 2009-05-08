
class Message < ActiveRecord::Base
  strip_attributes! # strip_attributes

  belongs_to :owner, :class_name => 'User', :foreign_key => 'owner_id'
  belongs_to :sender, :class_name => 'User', :foreign_key => 'sender_id'
  belongs_to :receiver, :class_name => 'User', :foreign_key => 'receiver_id'

  class NotOwnerError < StandardError
  end

  INBOX, OLDS, SENT, TRASH = 'inbox', 'olds', 'sent', 'trash'
  FOLDERS = [INBOX, OLDS, SENT, TRASH]

  attr_accessor :replying_to # holds username of user being replied

  validates_presence_of :receiver_id, :message => I18n.t('model.message.errors.receiver.invalid')
  validates_inclusion_of :folder, :in => FOLDERS, :message => 'invalid folder'

  def validate
    if self.receiver
      if !self.receiver.active?
        errors.add :receiver_id, I18n.t('model.message.errors.receiver.inactive')
      elsif self.receiver.system_user?
        errors.add :receiver_id, I18n.t('model.message.errors.receiver.system')
      end
    end
  end

  def before_save
    self.subject = self.subject[0, 50]
    self.body = self.body[0, 2000] if self.body
  end

  def self.valid_folder?(value)
    FOLDERS.include? value
  end

  def self.make_new(params, sender, args)
    m = new params
    if !args[:to].blank?
      m.owner = m.receiver = User.find_by_username(args[:to])
      m.sender = sender
      m.created_at = Time.now
      m.subject = I18n.t('model.message.new.no_subject') if m.subject.blank?
      m.unread = true
      m.folder = INBOX
    end
    if !args[:message_id].blank? # if replying or forwarding
      old_message = find args[:message_id]
      old_message.ensure_ownership sender
      prepare_for_reply m, old_message if args[:reply]
      prepare_for_forward m, old_message if args[:forward]
    end
    m
  end

  def self.user_messages(user, params, args)
    paginate_by_owner_id user,
                         :conditions => {:folder => args[:folder]},
                         :order => 'created_at DESC',
                         :page => current_page(params[:page]),
                         :per_page => args[:per_page]
  end

  def owned_by?(user)
    self.owner_id == user.id
  end

  def ensure_ownership(user)
    raise NotOwnerError unless owned_by? user
  end

  def set_read
    toggle! :unread if unread?
  end

  def deliver(replied_id)
    if valid?
      delete_replied(replied_id) if self.sender.delete_on_reply
      save
      save_sent if self.sender.save_sent
      return true
    end
    false
  end

  def move_to_folder(folder, mover)
    ensure_ownership mover
    update_attribute :folder, folder
  end
  
  private

  def self.prepare_for_reply(m, old_message)
    m.subject = "#{ 'Re: ' unless old_message.subject.starts_with?('Re:') }#{old_message.subject}"
    m.body = "\n\n\n----
              \n#{old_message.sender.username} #{I18n.t('model.message.prepare_to_reply.wrote')}:
              \n\n#{old_message.body}"
    m.replying_to = old_message.sender.username
  end

  def self.prepare_for_forward(m, old_message)
    m.subject = "#{ 'Fwd: ' unless old_message.subject.starts_with?('Fwd:') }#{old_message.subject}"
    m.body = "\n\n\n----
             \n#{old_message.sender.username} #{I18n.t('model.message.prepare_to_forward.wrote')}:
             \n\n#{old_message.body}"
  end

  def delete_replied(replied_id)
    unless replied_id.blank?
      m = find replied_id
      m.ensure_ownership self.sender
      m.update_attribute :folder, TRASH
    end
  end

  def save_sent
    clone = self.clone
    clone.owner = self.sender
    clone.folder = SENT
    clone.save
  end
end