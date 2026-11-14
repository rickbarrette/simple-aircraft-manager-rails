# The VAPID key pair that signs push notifications: VAPID_PUBLIC_KEY and
# VAPID_PRIVATE_KEY, or else a pair generated once and kept in
# storage/vapid_keys.json (backed up with the database). Changing the keys
# turns notifications off on every device until each turns them on again.
module PushKeys
  FILE = Rails.root.join("storage", "vapid_keys.json")

  module_function

  def public_key = keys["public_key"]
  def private_key = keys["private_key"]

  # Who push services contact about these notifications.
  def subject
    from = ENV["MAIL_FROM"].to_s[/[^<\s]+@[^>\s]+/]
    from ? "mailto:#{from}" : Sso.app_url
  end

  def keys
    @keys ||= if ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
      { "public_key" => ENV["VAPID_PUBLIC_KEY"], "private_key" => ENV["VAPID_PRIVATE_KEY"] }
    elsif FILE.exist?
      JSON.parse(FILE.read)
    else
      key = WebPush.generate_key
      { "public_key" => key.public_key, "private_key" => key.private_key }.tap do |pair|
        FILE.dirname.mkpath
        File.write(FILE, JSON.generate(pair), perm: 0o600)
      end
    end
  end
end
