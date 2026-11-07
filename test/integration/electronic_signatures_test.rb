require "test_helper"
require "pdf-reader"

# Electronic signatures on logbook entries, per AC 120-78B chapter 2.
class ElectronicSignaturesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @owner = create_user("owner@example.com").tap { _1.update!(name: "Owen Owner") }
    @mech = create_user("mech@example.com").tap { _1.update!(name: "Sam Mechanic") }
    @a = create_aircraft(owner: @owner, pilot: @mech, tail_number: "N12345")
    @ap = @mech.certificates.create!(kind: "AP", number: "7654321")
    @entry = @a.logbook_entries.create!(date: Date.new(2026, 10, 1), log_type: "AC", entry_type: "MAINTENANCE", aircraft_hours_at_entry: 1000,
                                        text: "Replaced left landing light lamp P/N 4509.", signoff_location: "KOQU")
  end

  def sign(entry = @entry, **params)
    post aircraft_logbook_entry_signature_path(@a, entry), params: { certificate_id: @ap.id, password: "test-password-123", confirm: "1" }.merge(params)
  end

  test "signing: review, certificate, password, confirmation; then the record shows who certified what and when" do
    sign_in @mech
    get aircraft_logbook_entry_path(@a, @entry)
    assert_select "a[href='#{new_aircraft_logbook_entry_signature_path(@a, @entry)}']", text: "Sign"
    get new_aircraft_logbook_entry_signature_path(@a, @entry)
    assert_includes response.body, "Replaced left landing light lamp P/N 4509."
    assert_includes response.body, "Certified by: “I certify that the work described in this entry was performed in accordance with 14 CFR Part 43"

    sign(confirm: "0")
    assert_response :unprocessable_entity
    assert_includes response.body, "Tick the box to confirm"
    sign(password: "wrong")
    assert_response :unprocessable_entity
    assert_includes response.body, "Re-enter your password"
    refute @entry.reload.signed?

    assert_emails 1 do
      sign
    end
    assert_redirected_to aircraft_logbook_entry_path(@a, @entry)
    sig = @entry.reload.signature
    assert_equal [ "Sam Mechanic", "AP", "7654321", "password", @mech ], [ sig.signer_name, sig.certificate_kind, sig.certificate_number, sig.auth_method, sig.user ]
    assert_equal [ "Sam Mechanic", "AP", "7654321" ], [ @entry.signoff_person, @entry.signoff_certificate_type, @entry.signoff_certificate_number ]
    assert_equal [ @entry.content_digest, :valid ], [ sig.content_digest, sig.status ]
    assert_equal "Replaced left landing light lamp P/N 4509.", JSON.parse(sig.content_snapshot)["text"]
    assert_equal "You signed a logbook entry for N12345", ActionMailer::Base.deliveries.last.subject
    assert_equal "Logbook entry signed electronically (2026-10-01)", @a.events.last.event_name

    get aircraft_logbook_entry_path(@a, @entry)
    assert_includes response.body, "Certified by Sam Mechanic, A&amp;P 7654321"
    assert_includes response.body, "Status: <strong>Valid</strong>"
    sign
    assert_response :unprocessable_entity # once only
    assert_includes response.body, "already signed"
  end

  test "signed entries are locked; tampering shows; edits go in a correction that supersedes the original" do
    sign_in @mech
    engine = create_component(@a, component_type: component_type("Engine"))
    filter = create_component(@a, component_type: component_type("Filter element"), parent_component: engine)
    @entry.update!(component: engine, component_hours_at_entry: 500)
    @entry.parts.create!(component: filter, hours_at_entry: 10)
    sign
    sign_in @owner
    get edit_aircraft_logbook_entry_path(@a, @entry)
    assert_redirected_to aircraft_logbook_entry_path(@a, @entry)
    patch aircraft_logbook_entry_path(@a, @entry), params: { logbook_entry: { text: "Changed" } }
    delete aircraft_logbook_entry_path(@a, @entry)
    assert_equal "Replaced left landing light lamp P/N 4509.", @entry.reload.text
    refute @entry.update(text: "Changed in the console")
    refute @entry.reload.destroy
    refute @entry.parts.first.update(hours_at_entry: 99)
    assert @entry.update(verified: false, page_number: 3) # not part of what was signed
    assert_raises(ActiveRecord::RecordNotSaved) { @entry.signature.update!(statement: "Different") }

    LogbookEntry.where(id: @entry.id).update_all(text: "Edited behind the app's back")
    assert_equal :altered, @entry.reload.signature.status
    LogbookEntry.where(id: @entry.id).update_all(text: "Replaced left landing light lamp P/N 4509.")
    EntrySignature.where(id: @entry.signature.id).update_all(certificate_number: "0000000")
    assert_equal :altered, @entry.reload.signature.status # the seal covers the signature too
    EntrySignature.where(id: @entry.signature.id).update_all(certificate_number: "7654321")
    assert_equal :valid, @entry.reload.signature.status

    get aircraft_logbook_entry_path(@a, @entry)
    assert_select "a[href='#{new_aircraft_logbook_entry_path(@a, supersedes: @entry.id)}']", text: "Correct this entry"
    get new_aircraft_logbook_entry_path(@a, supersedes: @entry.id)
    assert_select "input[name='logbook_entry[supersedes_id]'][value='#{@entry.id}']"
    assert_select "textarea[name='logbook_entry[text]']", text: "Replaced left landing light lamp P/N 4509."
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: {
      supersedes_id: @entry.id, date: "2026-10-01", log_type: "AC", entry_type: "MAINTENANCE", aircraft_hours_at_entry: 1000,
      text: "Replaced left landing light lamp P/N 4509-24." } }
    correction = @a.logbook_entries.find_by!(supersedes: @entry)
    refute @entry.reload.superseded? # until the correction is signed

    sign_in @mech
    sign(correction)
    assert @entry.reload.superseded?
    assert_equal [ :superseded, :valid ], [ @entry.signature.status, correction.reload.signature.status ]
    assert_equal @entry.signature.content_digest, JSON.parse(correction.signature.content_snapshot).dig("supersedes", "fingerprint")
    get new_aircraft_logbook_entry_path(@a, supersedes: @entry.id)
    assert_select "input[name='logbook_entry[supersedes_id]']", 0 # can't be corrected twice
  end

  test "who and what can sign" do
    pilot_cert = @owner.certificates.create!(kind: "PILOT", number: "1111111")
    expired = @mech.certificates.create!(kind: "IA", number: "7654321", expires_on: 1.day.ago.to_date)
    inspection = @a.logbook_entries.create!(date: Date.current, entry_type: "INSPECTION", text: "Annual per App. D", aircraft_hours_at_entry: 1000)
    assert_includes inspection.signing_problems(@ap), "an inspection entry needs its result (airworthy, or discrepancy list)"
    inspection.update!(inspection_result: "approved")
    assert_empty inspection.signing_problems(@ap)
    assert_includes inspection.signing_problems(pilot_cert), "a pilot certificate can sign preventive maintenance only"
    assert_includes inspection.signing_problems(expired), "that certificate has expired"
    assert_match "inspected in accordance with an annual inspection and was determined to be in airworthy condition", inspection.certification_statement("IA")
    assert_match "preventive maintenance", @entry.certification_statement("PILOT")

    sign_in @owner # signing with someone else's certificate
    post aircraft_logbook_entry_signature_path(@a, @entry), params: { certificate_id: @ap.id, password: "test-password-123", confirm: "1" }
    assert_includes response.body, "That certificate isn&#39;t yours"
    get new_aircraft_logbook_entry_signature_path(@a, @entry)
    assert_select "input[type=radio][value='#{pilot_cert.id}']:not([disabled])"

    @mech.update!(disabled_at: Time.current)
    assert_raises(EntrySigner::Error) { EntrySigner.new(@entry, user: @mech, certificate: @ap, auth_method: "password").sign! }
    post session_path, params: { email_address: "mech@example.com", password: "test-password-123" }
    assert_equal "This account is disabled.", flash[:alert]
  end

  test "single sign-on users sign after signing in again" do
    saved = %w[OIDC_ISSUER OIDC_CLIENT_ID].to_h { [ _1, ENV[_1] ] }
    ENV.update("OIDC_ISSUER" => "https://auth.example.com/", "OIDC_CLIENT_ID" => "sam")
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(provider: "oidc", uid: "sub-mech", info: { email: "mech@example.com" })
    @mech.update!(sso_uid: "sub-mech")
    sign_in @mech
    get new_aircraft_logbook_entry_signature_path(@a, @entry)
    assert_select "form[action='/auth/oidc'] input[name=prompt][value=login]"
    post aircraft_logbook_entry_signature_path(@a, @entry), params: { certificate_id: @ap.id, confirm: "1" }
    assert_response :unprocessable_entity # not signed in again yet

    post "/auth/oidc", params: { prompt: "login" }
    follow_redirect!
    assert_redirected_to new_aircraft_logbook_entry_signature_path(@a, @entry)
    post aircraft_logbook_entry_signature_path(@a, @entry), params: { certificate_id: @ap.id, confirm: "1" }
    assert_equal "sso", @entry.reload.signature.auth_method
  ensure
    saved.each { ENV[_1] = _2 }
    OmniAuth.config.mock_auth[:oidc] = nil
    OmniAuth.config.test_mode = false
  end

  test "an owner invites an outside mechanic, who signs that one entry with their own account" do
    sign_in @mech
    get new_aircraft_logbook_entry_signing_invitation_path(@a, @entry)
    assert_redirected_to aircraft_path(@a) # owners only

    sign_in @owner
    assert_emails 1 do
      perform_enqueued_jobs do
        post aircraft_logbook_entry_signing_invitations_path(@a, @entry), params: { signing_invitation: { email: "Outside@Example.com", message: "Thanks!" } }
      end
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "outside@example.com" ], mail.to
    path = mail.text_part.body.to_s[%r{http://example\.com(/sign/[\w-]+)}, 1]
    delete session_path

    get path
    assert_includes response.body, "sign in as <strong>outside@example.com</strong>"
    post "#{path}/account", params: { name: "Olive Outside", password: "longpassword1", password_confirmation: "longpassword1" }
    assert_redirected_to path
    follow_redirect!
    assert_select "form[action='#{certificates_path(return_to: path)}']" # add a certificate first
    post certificates_path(return_to: path), params: { user_certificate: { kind: "IA", number: "2222222" } }
    assert_redirected_to path
    outside = User.find_by!(email_address: "outside@example.com")
    get aircraft_path(@a)
    assert_response :not_found # no access to the aircraft itself

    post path, params: { certificate_id: outside.certificates.sole.id, password: "longpassword1", confirm: "1" }
    assert_redirected_to path
    sig = @entry.reload.signature
    assert_equal [ "Olive Outside", "IA", "2222222", outside ], [ sig.signer_name, sig.certificate_kind, sig.certificate_number, sig.user ]
    follow_redirect!
    assert_includes response.body, "Entry signed"

    sign_in @owner # someone else with the link: it's spent
    get path
    assert_response :not_found
  end

  test "printouts, archives and accounts" do
    sign_in @mech
    sign
    get aircraft_logbook_print_path(@a, format: :pdf), params: { ids: [ @entry.id ], layout: "letter" }
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join(" ").gsub(/\s+/, " ")
    assert_includes text, "Certified by Sam Mechanic, A&P 7654321"
    assert_includes text, "fingerprint #{@entry.signature.content_digest.first(16)}"
    assert_includes text, "I certify that the work described in this entry was performed in accordance with 14 CFR Part 43"

    path = File.join(Dir.mktmpdir, "a.sam.zip")
    AircraftArchive::Exporter.new(@a, source: "sam.example.com").write_to(path)
    copy = AircraftArchive::Importer.new(path, owner: @owner, tail_number: "N54321").run[:aircraft]
    imported = copy.logbook_entries.sole.signature
    assert_equal [ "Sam Mechanic", "sam.example.com", true ], [ imported.signer_name, imported.origin, imported.imported? ]
    assert copy.logbook_entries.sole.signed?

    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    delete admin_user_path(@mech)
    assert_match "disable the account instead", flash[:alert]
    patch disable_admin_user_path(@mech)
    assert @mech.reload.disabled?
    assert_equal :valid, @entry.reload.signature.status # their signatures stay
    patch enable_admin_user_path(@mech)
    refute @mech.reload.disabled?
  end
end
