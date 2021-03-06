class User < ActiveRecord::Base
  include UsersHelper
  include ActionView::Helpers
  include Rails.application.routes.url_helpers

  belongs_to :role


  has_secure_password

  before_validation :strip_whitespaces, :set_uuid, :set_name, :set_email_token, :set_role

  validates_presence_of :password, :password_confirmation, :email_token, on: :create
  validates_presence_of :name, :email, :ign

  validates_length_of :password, in: 8..256, on: [:create, :update], allow_nil: true
  validates_length_of :name, in: 2..30
  validates_length_of :about, maximum: 5000
  validates_length_of :ign, minimum: 1, maximum: 16

  validates :email, uniqueness: {case_sensitive: false}, format: {with: /\A.+@(.+\..{2,}|\[[0-9a-f:.]+\])\z/i, message: "That doesn't look like an email address."}
  validates :ign, uniqueness: {case_sensitive: false}, format: {with: /\A[a-z\d_]+\z/i, message: "Username is invalid (a-z, 0-9, _)."}

  validate :account_exists?, :if => lambda {|user| user.ign_changed? }

  has_many :blogposts
  has_many :comments

  # foo.bar.is?(current_user)
  def is? (user)
    self == user
  end

  def donor?
    !!self.donor
  end

  def confirmed?
    !!self.confirmed
  end

  def self.seen(time)
    # when you change this, change footer.html.erb as well?
    User.where("last_seen >= ?", time.ago).order("last_seen desc")
  end

  def online?
    last_seen && last_seen > 2.minutes.ago
  end

  #roles
  def disabled?
    !!(self.role == :disabled)
  end

  def banned?
    !!(self.role == :banned)
  end

  def normal?
    !!(self.role >= :normal)
  end

  def mod?
    !!(self.role >= :mod)
  end

  def admin?
    !!(self.role >= :admin)
  end

  def superadmin?
    !!(self.role >= :superadmin)
  end

  def avatar(size, options = {})
    options[:class]  ||= "avatar"
    options[:width]  ||= size
    options[:height] ||= size
    options[:alt]    ||= "avatar"
    return image_tag("https://crafatar.com/avatars/#{CGI.escape(self.uuid)}?size=#{size}&helm", options)
  end

  def to_s
    ign
  end



  #check if this user is an idiot and uses their mc password.
  def uses_mc_password?(password)
    uri = URI.parse("https://authserver.mojang.com/authenticate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 20
    http.use_ssl = true

    payload = { agent: { name: "Minecraft", version: 1 }, username: self.email, password: password }
    begin
      response = http.post(uri.request_uri, payload.to_json, "Content-Type" => "application/json").code
      if response == "200"
        return true
      else
        payload[:username] = self.ign
        return http.post(uri.request_uri, payload.to_json, "Content-Type" => "application/json").code == "200"
      end
    rescue => e
      Rails.logger.error "---"
      Rails.logger.error "ERROR: failed to check mc password for '#{self.uuid}'. Login servers down?"
      Rails.logger.error e.message
      Rails.logger.error "---"
      return false
    end
  end

  # def haspaid?
  #   begin
  #     response = open("https://sessionserver.mojang.com/session/minecraft/profile/#{CGI.escape(self.uuid)}", read_timeout: 0.5)
  #     if response.status[0] == "200"
  #       session_profile = JSON.load(response.read)
  #       # unpaid accounts are called 'demo' accounts
  #       return session_profile["demo"] == true
  #     elsif response.status[0] == "204"
  #       # user doesn't exist
  #       return false
  #     else
  #       Rails.logger.error "---"
  #       Rails.logger.error "ERROR: unexpected response code while checking '#{self.uuid}' for premium account"
  #       Rails.logger.error "code: #{reponse.status}, body: '#{reponse.read}'"
  #       Rails.logger.error "---"
  #     end
  #   rescue => e
  #     Rails.logger.error "---"
  #     Rails.logger.error "ERROR: failed to check for premium account for '#{self.uuid}'. Minecraft servers down?"
  #     Rails.logger.error e.message
  #     Rails.logger.error "---"
  #   end
  #   # mojang servers have trouble
  #   return true
  # end

  # def correct_case?(ign)
  #   begin
  #     http = Net::HTTP.start("skins.minecraft.net")
  #     skin = http.get("/MinecraftSkins/#{CGI.escape(ign)}.png")
  #     http.finish
  #   rescue
  #     Rails.logger.error "---"
  #     Rails.logger.error "ERROR: failed to get skin status code for '#{ign}'. Skin servers down?"
  #     Rails.logger.error "---"
  #   end
  #   skin.code != "404"
  # end

  def get_profile
    uri  = URI.parse("https://api.mojang.com/profiles/minecraft")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 20
    http.use_ssl = true

    begin
      response = http.post(uri.request_uri, [self.ign].to_json, "Content-Type" => "application/json")
      if response.code == "200"
        data = JSON.load(response.body)
        if data.length == 1
          return data[0]
        elsif data.length > 1
          raise "Multiple accounts for user #{self.ign}: '#{response.body}'"
        elsif data.length < 1
          return nil
        end
      end
    rescue => e
      Rails.logger.error "----"
      Rails.logger.error "Failed to get mojang profile for #{self.ign}"
      Rails.logger.error e.message
      Rails.logger.error "----"
      return nil
    end
  end


  def to_param
    [id, to_s.parameterize].join("-")
  end




  private

  def set_role
    self.role ||= Role.get(:normal)
  end

  def set_uuid
    if !self.uuid.present?
      # idk
    end
  end

  def set_name
    self.name ||= self.ign
  end

  def account_exists?
    profile = self.get_profile
    if !profile || profile["demo"] == true
      errors.add(:ign, "'#{self.ign}' is not a paid account!")
    end
  end

  def strip_whitespaces
    self.name.strip! if self.name
    self.ign.strip! if self.ign
    self.email.strip! if self.email
    self.about.strip! if self.about
    self.skype.strip! if self.skype
    self.youtube.strip! if self.youtube
    self.twitter.strip! if self.twitter
  end

  def set_email_token
    self.email_token ||= SecureRandom.hex(16)
  end

  # def ign_is_not_skull
  #   errors.add(:ign, "Good one...") if ["MHF_Blaze", "MHF_CaveSpider", "MHF_Chicken", "MHF_Cow", "MHF_Enderman", "MHF_Ghast", "MHF_Golem", "MHF_Herobrine", "MHF_LavaSlime", "MHF_MushroomCow", "MHF_Ocelot", "MHF_Pig", "MHF_PigZombie", "MHF_Sheep", "MHF_Slime", "MHF_Spider", "MHF_Squid", "MHF_Villager", "MHF_Cactus", "MHF_Cake", "MHF_Chest", "MHF_Melon", "MHF_OakLog", "MHF_Pumpkin", "MHF_TNT", "MHF_TNT2", "MHF_ArrowUp", "MHF_ArrowDown", "MHF_ArrowLeft", "MHF_ArrowRight", "MHF_Exclamation", "MHF_Question"].include?(self.ign)
  # end

  # def ign_is_not_mojang
  #   if self.ign.start_with?("mojang_secret_ign_")
  #     self.ign = self.ign[18..-1]
  #   else
  #     errors.add(:ign, "If that's really you, contact <a href='/users?role=staff'>us</a> in-game.") if ["mollstam", "carlmanneh", "MinecraftChick", "Notch", "jeb_", "xlson", "jonkagstrom", "KrisJelbring", "marc", "Marc_IRL", "MidnightEnforcer", "YoloSwag4Lyfe", "EvilSeph", "Grumm", "Dinnerbone", "geuder", "eldrone", "JahKob", "BomBoy", "MansOlson", "pgeuder", "91maan90", "vubui", "PoiPoiChen", "mamirm", "eldrone", "_tomcc"].include?(self.ign)
  #   end
  # end
end