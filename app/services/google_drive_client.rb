require "net/http"

# Minimal Google Drive v3 client for the off-site backup: OAuth (offline
# access, drive.file scope), folders, resumable uploads, listing,
# downloading and deleting the files this app created.
class GoogleDriveClient
  class Error < StandardError; end
  class AuthError < Error; end # revoked or wrong credentials: reconnect

  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth".freeze
  TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze
  API = "https://www.googleapis.com/drive/v3".freeze
  UPLOAD = "https://www.googleapis.com/upload/drive/v3/files".freeze
  SCOPE = "https://www.googleapis.com/auth/drive.file".freeze
  FOLDER = "application/vnd.google-apps.folder".freeze

  def self.authorize_url(client_id:, redirect_uri:, state:)
    "#{AUTH_URL}?#{URI.encode_www_form(client_id: client_id, redirect_uri: redirect_uri, response_type: 'code', scope: SCOPE,
                                        access_type: 'offline', prompt: 'consent', include_granted_scopes: 'true', state: state)}"
  end

  # The refresh token from the code Google sent back.
  def self.exchange_code(client_id:, client_secret:, code:, redirect_uri:)
    token = token_request(client_id: client_id, client_secret: client_secret, code: code, redirect_uri: redirect_uri, grant_type: "authorization_code")
    token["refresh_token"].presence or raise AuthError, I18n.t("services.google_drive.google_didn_t_return_a")
  end

  def self.revoke(token)
    res = Net::HTTP.post_form(URI(REVOKE_URL), token: token)
    raise Error, I18n.t("services.google_drive.revoke_failed", code: res.code) unless res.is_a?(Net::HTTPSuccess)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, e.message
  end

  def self.token_request(**form)
    res = Net::HTTP.post_form(URI(TOKEN_URL), form)
    body = JSON.parse(res.body) rescue {}
    return body if res.is_a?(Net::HTTPSuccess)
    raise AuthError, I18n.t("services.google_drive.refused_credentials", reason: body["error_description"] || body["error"] || res.code) if res.code.to_i.in?([ 400, 401 ])
    raise Error, I18n.t("services.google_drive.google_token_request_failed", code: res.code)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, I18n.t("services.google_drive.couldn_t_reach_google", message: e.message)
  end

  def initialize(client_id:, client_secret:, refresh_token:)
    @client_id = client_id
    @client_secret = client_secret
    @refresh_token = refresh_token
  end

  def account_email = request(:get, "#{API}/about", query: { fields: "user(emailAddress)" }).dig("user", "emailAddress")

  def folder?(id)
    file = request(:get, "#{API}/files/#{CGI.escape(id)}", query: { fields: "id,mimeType,trashed" })
    file["mimeType"] == FOLDER && !file["trashed"]
  rescue Error => e
    raise if e.is_a?(AuthError)
    false
  end

  def create_folder(name, parent: nil)
    request(:post, "#{API}/files", query: { fields: "id" }, json: { name: name, mimeType: FOLDER, parents: Array(parent) }).fetch("id")
  end

  # Uploads an IO of known size (resumable session, one PUT); returns the file id.
  def upload(io, name:, parent:, size:, content_type: "application/octet-stream", properties: {})
    session = request(:post, UPLOAD, query: { uploadType: "resumable", fields: "id" },
                                     json: { name: name, parents: [ parent ], appProperties: properties },
                                     headers: { "X-Upload-Content-Type" => content_type, "X-Upload-Content-Length" => size.to_s }, raw: true)
    location = session["Location"] or raise Error, I18n.t("services.google_drive.google_didn_t_start_the")
    put = Net::HTTP::Put.new(URI(location))
    put["Content-Length"] = size.to_s
    put["Content-Type"] = content_type
    put.body_stream = io
    JSON.parse(perform(URI(location), put, timeout: 3600).body).fetch("id")
  end

  # [{ "id", "name", "size", "createdTime", "appProperties" }] in a folder.
  def list(parent)
    files = []
    page = nil
    loop do
      q = { q: "'#{parent.gsub("'", "")}' in parents and trashed = false", pageSize: 1000,
            fields: "nextPageToken,files(id,name,size,createdTime,appProperties)", orderBy: "name" }
      q[:pageToken] = page if page
      body = request(:get, "#{API}/files", query: q)
      files.concat(body.fetch("files", []))
      page = body["nextPageToken"] or break
    end
    files
  end

  # Streams a file's content into the IO.
  def download(id, to:)
    uri = URI("#{API}/files/#{CGI.escape(id)}?alt=media")
    get = Net::HTTP::Get.new(uri)
    get["Authorization"] = "Bearer #{access_token}"
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 600) do |http|
      http.request(get) do |res|
        raise_for(res) unless res.is_a?(Net::HTTPSuccess)
        res.read_body { to.write(_1) }
      end
    end
    to.rewind if to.respond_to?(:rewind)
    to
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, I18n.t("services.google_drive.couldn_t_reach_google_drive", message: e.message)
  end

  def delete(id) = request(:delete, "#{API}/files/#{CGI.escape(id)}")

  private

  def access_token
    return @access_token if @access_token && @expires_at > Time.current
    token = self.class.token_request(client_id: @client_id, client_secret: @client_secret, refresh_token: @refresh_token, grant_type: "refresh_token")
    @expires_at = Time.current + token.fetch("expires_in", 3600).to_i - 60
    @access_token = token.fetch("access_token")
  end

  def request(method, url, query: nil, json: nil, headers: {}, raw: false)
    uri = URI(url)
    uri.query = URI.encode_www_form(query) if query
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    headers.each { req[_1] = _2 }
    if json
      req["Content-Type"] = "application/json; charset=UTF-8"
      req.body = json.to_json
    end
    res = perform(uri, req)
    return res if raw
    res.body.present? ? JSON.parse(res.body) : {}
  end

  def perform(uri, req, timeout: 60)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: timeout, write_timeout: timeout) { _1.request(req) }
    raise_for(res) unless res.is_a?(Net::HTTPSuccess)
    res
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
    raise Error, I18n.t("services.google_drive.couldn_t_reach_google_drive", message: e.message)
  end

  def raise_for(res)
    message = (JSON.parse(res.body.to_s).dig("error", "message") rescue nil) || res.message
    raise AuthError, I18n.t("services.google_drive.google_drive_refused_access_connect", message: message) if res.code.to_i == 401
    raise Error, I18n.t("services.google_drive.google_drive", message: message, code: res.code)
  end
end
