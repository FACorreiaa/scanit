# Sets up the ScanItNow App Store record through the App Store Connect API (docs/release.md, fast path).
# Idempotent: safe to re-run after editing scanit/fastlane/metadata.
#
#   ASC_KEY_PATH=~/Downloads/AuthKey_46PLPRZ868.p8 ruby scanit/fastlane/asc_setup.rb
#
# Covers what fastlane cannot do with an API key (current pricing API, 2025 age-rating fields,
# availability) plus the text fields. Screenshots go through `fastlane deliver`. App Privacy ("Data
# Not Collected") is not exposed by Apple's API and must be answered once in App Store Connect.
require_relative "asc_api"

app = app_for(BUNDLE_ID) or abort("no app for #{BUNDLE_ID}")
app_id = app["id"]
puts "App #{app['attributes']['name']} (#{app_id})"

step "content rights: uses third-party content (Open Food Facts)"
api(:patch, "/v1/apps/#{app_id}", { data: { type: "apps", id: app_id,
  attributes: { contentRightsDeclaration: "USES_THIRD_PARTY_CONTENT" } } })

info = api(:get, "/v1/apps/#{app_id}/appInfos")["data"].find { |i| i["attributes"]["state"] != "READY_FOR_DISTRIBUTION" } ||
       api(:get, "/v1/apps/#{app_id}/appInfos")["data"].first
info_id = info["id"]

step "categories: #{text('primary_category.txt')} / #{text('secondary_category.txt')}"
api(:patch, "/v1/appInfos/#{info_id}", { data: { type: "appInfos", id: info_id, relationships: {
  primaryCategory: { data: { type: "appCategories", id: text("primary_category.txt") } },
  secondaryCategory: { data: { type: "appCategories", id: text("secondary_category.txt") } },
} } })

step "app info (#{LOCALE}): name, subtitle, privacy policy URL"
info_loc = api(:get, "/v1/appInfos/#{info_id}/appInfoLocalizations")["data"].find { |l| l["attributes"]["locale"] == LOCALE }
api(:patch, "/v1/appInfoLocalizations/#{info_loc['id']}", { data: { type: "appInfoLocalizations", id: info_loc["id"], attributes: {
  name: text("#{LOCALE}/name.txt"), subtitle: text("#{LOCALE}/subtitle.txt"), privacyPolicyUrl: text("#{LOCALE}/privacy_url.txt"),
} } })

step "age rating: none of the content descriptors → 4+"
rating = api(:get, "/v1/appInfos/#{info_id}/ageRatingDeclaration")["data"]
none = %w[alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated gunsOrOtherWeapons horrorOrFearThemes
          matureOrSuggestiveThemes medicalOrTreatmentInformation profanityOrCrudeHumor sexualContentGraphicAndNudity
          sexualContentOrNudity violenceCartoonOrFantasy violenceRealisticProlongedGraphicOrSadistic violenceRealistic]
no = %w[advertising ageAssurance gambling healthOrWellnessTopics lootBox messagingAndChat parentalControls
        unrestrictedWebAccess userGeneratedContent]
attributes = {}
none.each { |k| attributes[k] = "NONE" if rating["attributes"].key?(k) }
no.each { |k| attributes[k] = false if rating["attributes"].key?(k) }
api(:patch, "/v1/ageRatingDeclarations/#{rating['id']}", { data: { type: "ageRatingDeclarations", id: rating["id"], attributes: attributes } })

version = api(:get, "/v1/apps/#{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED")["data"].first or abort("no editable version")
version_id = version["id"]
step "version #{version['attributes']['versionString']}: copyright, manual release"
api(:patch, "/v1/appStoreVersions/#{version_id}", { data: { type: "appStoreVersions", id: version_id, attributes: {
  copyright: text("copyright.txt"), releaseType: "MANUAL",
} } })

step "version text (#{LOCALE}): description, keywords, promotional text, URLs"
version_loc = api(:get, "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations")["data"].find { |l| l["attributes"]["locale"] == LOCALE }
api(:patch, "/v1/appStoreVersionLocalizations/#{version_loc['id']}", { data: { type: "appStoreVersionLocalizations", id: version_loc["id"], attributes: {
  description: text("#{LOCALE}/description.txt"), keywords: text("#{LOCALE}/keywords.txt"),
  promotionalText: text("#{LOCALE}/promotional_text.txt"), supportUrl: text("#{LOCALE}/support_url.txt"),
  marketingUrl: text("#{LOCALE}/marketing_url.txt"),
} } })

step "App Review contact and notes (contact copied from #{REVIEW_CONTACT_FROM})"
source_app = app_for(REVIEW_CONTACT_FROM) or abort("no app for #{REVIEW_CONTACT_FROM}")
source_version = api(:get, "/v1/apps/#{source_app['id']}/appStoreVersions?limit=1")["data"].first
contact = api(:get, "/v1/appStoreVersions/#{source_version['id']}/appStoreReviewDetail")&.dig("data", "attributes") or abort("no review contact to copy")
review_attributes = {
  contactFirstName: text("review_information/first_name.txt"), contactLastName: text("review_information/last_name.txt"),
  contactEmail: contact["contactEmail"], contactPhone: contact["contactPhone"],
  notes: text("review_information/notes.txt"), demoAccountRequired: false,
}
existing = api(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")&.dig("data")
if existing
  api(:patch, "/v1/appStoreReviewDetails/#{existing['id']}", { data: { type: "appStoreReviewDetails", id: existing["id"], attributes: review_attributes } })
else
  api(:post, "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: review_attributes,
    relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })
end

step "price: Free"
schedule = api(:get, "/v1/apps/#{app_id}/appPriceSchedule?include=manualPrices")
if schedule && Array(schedule.dig("data", "relationships", "manualPrices", "data")).any?
  puts "  already set"
else
  points = api(:get, "/v1/apps/#{app_id}/appPricePoints?filter[territory]=USA&limit=200")["data"]
  free = points.find { |p| p["attributes"]["customerPrice"].to_f.zero? } or abort("no free price point")
  api(:post, "/v1/appPriceSchedules", {
    data: { type: "appPriceSchedules", relationships: {
      app: { data: { type: "apps", id: app_id } },
      baseTerritory: { data: { type: "territories", id: "USA" } },
      manualPrices: { data: [{ type: "appPrices", id: "${free}" }] },
    } },
    included: [{ type: "appPrices", id: "${free}", attributes: { startDate: nil },
                 relationships: { appPricePoint: { data: { type: "appPricePoints", id: free["id"] } } } }],
  })
end

step "availability: every territory, and new ones automatically"
if api(:get, "/v1/apps/#{app_id}/appAvailabilityV2")
  puts "  already set"
else
  territories = api(:get, "/v1/territories?limit=200")["data"].map { |t| t["id"] }
  api(:post, "/v2/appAvailabilities", {
    data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true }, relationships: {
      app: { data: { type: "apps", id: app_id } },
      territoryAvailabilities: { data: territories.map { |t| { type: "territoryAvailabilities", id: "${#{t}}" } } },
    } },
    included: territories.map { |t| { type: "territoryAvailabilities", id: "${#{t}}", attributes: { available: true },
                                       relationships: { territory: { data: { type: "territories", id: t } } } } },
  })
  puts "  #{territories.count} territories"
end

puts "Done. Still manual: App Privacy → \"Data Not Collected\" (not in Apple's API)."
