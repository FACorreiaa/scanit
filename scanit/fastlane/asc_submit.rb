# Attaches the newest processed build to the editable ScanItNow version and submits it for App Review.
#
#   ruby scanit/fastlane/asc_submit.rb            # attach + submit
#   ruby scanit/fastlane/asc_submit.rb --dry-run  # attach only, report what Apple still wants
#
# Run after the `release` lane has uploaded a build. Apple reports anything still missing
# (for example App Privacy, which its API cannot answer) when the submission is created.
require_relative "asc_api"

dry_run = ARGV.include?("--dry-run")
app = app_for(BUNDLE_ID) or abort("no app for #{BUNDLE_ID}")
app_id = app["id"]
version = api(:get, "/v1/apps/#{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED")["data"].first or abort("no editable version")
version_id = version["id"]
version_string = version["attributes"]["versionString"]

# Newest build for this marketing version that has finished processing.
build = nil
40.times do
  builds = api(:get, "/v1/builds?filter[app]=#{app_id}&filter[preReleaseVersion.version]=#{version_string}&sort=-uploadedDate&limit=5")["data"]
  build = builds.find { |b| b["attributes"]["processingState"] == "VALID" && !b["attributes"]["expired"] }
  break if build
  latest = builds.first
  puts "waiting for processing (latest: #{latest ? "#{latest['attributes']['version']} #{latest['attributes']['processingState']}" : 'none uploaded yet'})"
  sleep 30
end
build or abort("no processed build for #{version_string}")
puts "Build #{build['attributes']['version']} (#{build['id']}) → version #{version_string}"
api(:patch, "/v1/appStoreVersions/#{version_id}/relationships/build", { data: { type: "builds", id: build["id"] } })

exit 0 if dry_run

submission = api(:post, "/v1/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
  relationships: { app: { data: { type: "apps", id: app_id } } } } })["data"]
api(:post, "/v1/reviewSubmissionItems", { data: { type: "reviewSubmissionItems", relationships: {
  reviewSubmission: { data: { type: "reviewSubmissions", id: submission["id"] } },
  appStoreVersion: { data: { type: "appStoreVersions", id: version_id } },
} } })
api(:patch, "/v1/reviewSubmissions/#{submission['id']}", { data: { type: "reviewSubmissions", id: submission["id"],
  attributes: { submitted: true } } })
puts "Submitted #{version_string} (build #{build['attributes']['version']}) for App Review."
