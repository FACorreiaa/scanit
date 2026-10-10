# Shared App Store Connect API helpers for asc_setup.rb and asc_submit.rb (team key 46PLPRZ868).
require "json"
require "net/http"
require "spaceship"

KEY_ID = ENV.fetch("ASC_KEY_ID", "46PLPRZ868")
ISSUER = ENV.fetch("ASC_ISSUER_ID", "7382d47b-5a08-4122-a9ed-4ded697ade84")
KEY_PATH = File.expand_path(ENV.fetch("ASC_KEY_PATH", "~/Downloads/AuthKey_46PLPRZ868.p8"))
BUNDLE_ID = "com.fernandocorreia.scanit"
REVIEW_CONTACT_FROM = "facorreia.financeplan" # reuse the App Review contact already on Norviq's record
LOCALE = "en-GB"
META = File.join(__dir__, "metadata")

TOKEN = Spaceship::ConnectAPI::Token.create(key_id: KEY_ID, issuer_id: ISSUER, filepath: KEY_PATH)

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri)
  TOKEN.refresh! if TOKEN.expired?
  request["Authorization"] = "Bearer #{TOKEN.text}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  return nil if response.code == "404" && method == :get
  raise "#{method.upcase} #{path} → #{response.code}: #{response.body[0, 800]}" if response.code.to_i >= 400
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

def text(path) = File.read(File.join(META, path)).strip

# filter[bundleId] matches by prefix ("…scanit" also returns "…scanit.beta"), so insist on an exact match.
def app_for(bundle_id)
  api(:get, "/v1/apps?filter[bundleId]=#{bundle_id}")["data"].find { |a| a["attributes"]["bundleId"] == bundle_id }
end
def step(name) = puts("• #{name}")

