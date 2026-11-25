# Attaches a processed build to the editable ScanItNow version and submits it for App Review.
#
#   ruby scanit/fastlane/asc_submit.rb --status        # read only: versions, submissions, builds
#   ruby scanit/fastlane/asc_submit.rb --build 7       # attach build 7 (waits for it) + submit
#   ruby scanit/fastlane/asc_submit.rb                 # attach the newest upload (waits) + submit
#   ruby scanit/fastlane/asc_submit.rb --dry-run       # attach only, no submit
#
# Run after the `release` lane has uploaded a build (CI: the `submit_status` and `submit` lanes).
# Apple reports anything still missing (for example App Privacy, which its API cannot answer) when
# the submission is created. A submission Apple sent back (UNRESOLVED_ISSUES) is resubmitted, never
# cancelled.
require_relative "asc_api"

dry_run = ARGV.include?("--dry-run")
status_only = ARGV.include?("--status")
wanted_build = ARGV.index("--build")&.then { |i| ARGV.fetch(i + 1) }
app = app_for(BUNDLE_ID) or abort("no app for #{BUNDLE_ID}")
app_id = app["id"]

if status_only
  puts "Versions:"
  api(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=10")["data"].each do |v|
    puts "  #{v['attributes']['versionString']}  #{v['attributes']['appStoreState']}"
  end
  puts "Review submissions:"
  api(:get, "/v1/reviewSubmissions?filter[app]=#{app_id}&limit=10")["data"].each do |r|
    puts "  #{r['id']}  #{r['attributes']['state']}  submitted #{r['attributes']['submittedDate'] || '-'}"
  end
  puts "Builds (newest first):"
  api(:get, "/v1/builds?filter[app]=#{app_id}&sort=-uploadedDate&limit=5&include=preReleaseVersion")["data"].each do |b|
    puts "  #{b['attributes']['version']}  #{b['attributes']['processingState']}  uploaded #{b['attributes']['uploadedDate']}"
  end
  exit 0
end

version = api(:get, "/v1/apps/#{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED")["data"].first or abort("no editable version")
version_id = version["id"]
version_string = version["attributes"]["versionString"]

# A submission Apple sent back (rejected) is resubmitted, like App Store Connect's "Resubmit to App
# Review": its items are marked resolved and it is submitted again. It is never cancelled.
unresolved = api(:get, "/v1/reviewSubmissions?filter[app]=#{app_id}&filter[platform]=IOS&filter[state]=UNRESOLVED_ISSUES")["data"].first

# The build to send: the one asked for, or the newest upload. Never an older build that happens to
# be processed while the new one is still processing.
build = nil
40.times do
  builds = api(:get, "/v1/builds?filter[app]=#{app_id}&filter[preReleaseVersion.version]=#{version_string}&sort=-uploadedDate&limit=10")["data"]
  candidate = wanted_build ? builds.find { |b| b["attributes"]["version"] == wanted_build } : builds.first
  if candidate && candidate["attributes"]["processingState"] == "VALID" && !candidate["attributes"]["expired"]
    build = candidate
    break
  end
  abort("build #{candidate['attributes']['version']} is #{candidate['attributes']['processingState']}") if candidate && %w[FAILED INVALID].include?(candidate["attributes"]["processingState"])
  puts "waiting for processing (#{candidate ? "#{candidate['attributes']['version']} #{candidate['attributes']['processingState']}" : "build #{wanted_build || '?'} not uploaded yet"})"
  sleep 30
end
build or abort("no processed build for #{version_string}")
puts "Build #{build['attributes']['version']} (#{build['id']}) → version #{version_string}"
api(:patch, "/v1/appStoreVersions/#{version_id}/relationships/build", { data: { type: "builds", id: build["id"] } })

exit 0 if dry_run

if unresolved
  items = api(:get, "/v1/reviewSubmissions/#{unresolved['id']}/items?include=appStoreVersion")["data"]
  items.each do |item|
    puts "item #{item['id']}: #{item['attributes']['state']}"
    next if item["attributes"]["resolved"]
    api(:patch, "/v1/reviewSubmissionItems/#{item['id']}", { data: { type: "reviewSubmissionItems", id: item["id"],
      attributes: { resolved: true } } })
  end
  api(:patch, "/v1/reviewSubmissions/#{unresolved['id']}", { data: { type: "reviewSubmissions", id: unresolved["id"],
    attributes: { submitted: true } } })
  puts "Resubmitted #{version_string} (build #{build['attributes']['version']}) for App Review, submission #{unresolved['id']}."
  exit 0
end

# Apple allows one open submission per platform: reuse it (a failed earlier run leaves one behind).
submission = api(:get, "/v1/reviewSubmissions?filter[app]=#{app_id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW")["data"].first
submission ||= api(:post, "/v1/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" },
  relationships: { app: { data: { type: "apps", id: app_id } } } } })["data"]
items = api(:get, "/v1/reviewSubmissions/#{submission['id']}/items?include=appStoreVersion")["data"]
unless items.any? { |i| i.dig("relationships", "appStoreVersion", "data", "id") == version_id }
  api(:post, "/v1/reviewSubmissionItems", { data: { type: "reviewSubmissionItems", relationships: {
    reviewSubmission: { data: { type: "reviewSubmissions", id: submission["id"] } },
    appStoreVersion: { data: { type: "appStoreVersions", id: version_id } },
  } } })
end
api(:patch, "/v1/reviewSubmissions/#{submission['id']}", { data: { type: "reviewSubmissions", id: submission["id"],
  attributes: { submitted: true } } })
puts "Submitted #{version_string} (build #{build['attributes']['version']}) for App Review."
