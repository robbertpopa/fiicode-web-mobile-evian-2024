require 'bcrypt'

class BaseLogin
  include Mongoid::Document
  include Mongoid::Timestamps
  include BCrypt

  field :username, type: String
  field :hashed_password, type: String

  validates_uniqueness_of :username, case_sensitive: false
  validates_presence_of :username, :hashed_password

  def initialize(attrs = {})
    raise NoMethodError, "Cannot initialize base class" unless self.class < BaseLogin

    [:username, :password].all? { |key| attrs.include?(key) } or raise ArgumentError

    super()
    self.username = attrs[:username]
    self.password = attrs[:password]
  end

  def username=(username)
    invalid_msg = "Usernames can only contain letters [a-z], numbers [0-9], and underscores [_]"

    raise ArgumentError, invalid_msg unless /\A[a-z0-9_]+\z/.match?(username)

    write_attribute(:username, username.strip)
  end

  def password=(password)
    raise ArgumentError, "Password cannot contain spaces" if password.include?(" ")

    weak_password_msg = "Passwords must be at least 8 characters long, contain at least one uppercase letter, one lowercase letter, one number, and one special character"
    unless /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%\^&\*])/.match?(password) && password.length >= 8
      raise ArgumentError, weak_password_msg if Rails.env.production?
      puts "Annoying restriction disabled in development environment: #{weak_password_msg}"
    end

    @password = Password.create(password)
    write_attribute(:hashed_password, @password)
  end

  def password
    @password ||= Password.new(read_attribute(:hashed_password))
  end

  def self.authenticate(username, password)
    raise NoMethodError, "Cannot call factory on the base class" unless self < BaseLogin

    return nil unless username && password

    login = self.find_by(username: username.strip) rescue nil
    return nil unless login && login.password == password

    login
  end

  def _migrate_password(password)
    self.password = password
  end
end
