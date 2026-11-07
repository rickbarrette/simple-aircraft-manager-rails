require "test_helper"
require "pdf-reader"

class LogbookPrintTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", make: "Cessna", model: "172N", serial_number: "17200001")
    @entry = @a.logbook_entries.create!(date: Date.new(2026, 10, 1), log_type: "AC", entry_type: "MAINTENANCE", aircraft_hours_at_entry: 1234.5,
                                        text: "Replaced left landing light lamp P/N 4509 — checked “OK”. ✈", signoff_person: "Sam Mechanic",
                                        signoff_certificate_type: "AP", signoff_certificate_number: "7654321", signoff_location: "KOQU")
  end

  def pdf(params)
    get aircraft_logbook_print_path(@a, format: :pdf), params: params
    assert_response :success
    assert_equal "application/pdf", response.media_type
    PDF::Reader.new(StringIO.new(response.body))
  end

  def text_of(reader) = reader.pages.map(&:text).join("\n").gsub(/\s+/, " ")

  test "an entry prints with what 43.9 wants and a line to sign" do
    sign_in @pilot
    get aircraft_logbook_entry_path(@a, @entry)
    assert_select "a[href='#{new_aircraft_logbook_print_path(@a, ids: [ @entry.id ])}']", text: "Print for logbook"
    get new_aircraft_logbook_print_path(@a, ids: [ @entry.id ])
    assert_select "input[type=radio][name=layout]", LogbookEntryPdf::LAYOUTS.size
    assert_select "form[target=_blank][action='#{aircraft_logbook_print_path(@a, format: :pdf)}']"

    reader = pdf(ids: [ @entry.id ], layout: "avery_5164")
    text = text_of(reader)
    [ "N12345", "Cessna 172N", "S/N 17200001", "Aircraft log", "Date: Oct 1, 2026", "Total time: 1234.5 hrs (tach)",
      "Replaced left landing light lamp P/N 4509 — checked “OK”. ?", "Signature", "Sam Mechanic", "KOQU", "A&P No. 7654321" ].each do |s|
      assert_includes text, s
    end
    assert_equal [ 1, [ 612, 792 ] ], [ reader.page_count, reader.pages.first.attributes[:MediaBox].last(2).map(&:round) ]
    assert_equal "Logbook entries printed (1)", @a.events.last.event_name
  end

  test "inspection entries get the 43.11 statement unless they already certify" do
    annual = InspectionType.create!(name: "Annual inspection (91.409(a))", recurring: true, recurring_months: 12).tap { _1.aircraft << @a }
    inspection = @a.logbook_entries.create!(date: Date.new(2026, 9, 1), entry_type: "INSPECTION", text: "Performed annual per Part 43 App. D.",
                                            inspection_result: "approved")
    @a.inspection_records.create!(inspection_type: annual, date: inspection.date, logbook_entry: inspection)
    found = @a.logbook_entries.create!(date: Date.new(2026, 9, 2), entry_type: "INSPECTION", text: "100 hour inspection.", inspection_result: "discrepancies")
    already = @a.logbook_entries.create!(date: Date.new(2026, 9, 3), entry_type: "INSPECTION", inspection_result: "approved",
                                         text: "I certify that this aircraft has been inspected in accordance with an annual inspection.")
    sign_in @owner
    text = text_of(pdf(ids: [ inspection.id, found.id, already.id ], layout: "letter"))
    assert_includes text, "inspected in accordance with an annual inspection and was determined to be in airworthy condition"
    assert_includes text, "in accordance with a 100-hour inspection and a list of discrepancies and unairworthy items dated Sep 2, 2026"
    assert_equal 2, text.scan("I certify").size - 1 # the third already had its own
    assert_includes text, "Cert. No. __________" # nothing recorded: blanks to fill by hand
  end

  test "labels fill across then down, can start partway through a sheet, and long entries continue" do
    entries = 7.times.map { |i| @a.logbook_entries.create!(date: Date.new(2026, 1, i + 1), text: "Entry #{i}") }
    sign_in @owner
    assert_equal 2, pdf(ids: entries.map(&:id), layout: "avery_5164").page_count # 6 per sheet
    assert_equal 1, pdf(ids: entries.map(&:id), layout: "avery_5163").page_count # 10 per sheet
    assert_equal 2, pdf(ids: entries.first(2).map(&:id), layout: "avery_5164", start_at: 6).page_count
    assert_equal 2, pdf(ids: entries.map(&:id), layout: "half_letter").page_count # pages: entries follow one another
    assert_equal [ 396, 612 ], pdf(ids: [ entries.first.id ], layout: "half_letter").pages.first.attributes[:MediaBox].last(2).map(&:round)

    long = @a.logbook_entries.create!(date: Date.current, text: (1..200).map { "Step #{_1} done." }.join(" "))
    text = text_of(pdf(ids: [ long.id ], layout: "avery_5163"))
    assert_includes text, "Continued on the next label."
    assert_includes text, "Aircraft log (continued)"
    # Counted on single-column pages (side-by-side labels interleave when text is extracted).
    longer = @a.logbook_entries.create!(date: Date.current, text: (1..3000).map { "w#{_1}" }.join(" ")) # words can't split across pages
    reader = pdf(ids: [ longer.id ], layout: "half_letter")
    assert_operator reader.page_count, :>, 1
    assert_includes text_of(reader), "N12345 · page 2 of #{reader.page_count}"
    assert_equal (1..3000).to_a, text_of(reader).scan(/\bw(\d+)\b/).flatten.map(&:to_i) # in order, nothing lost
  end

  test "pick several entries on the list; outsiders can't print" do
    other = @a.logbook_entries.create!(date: Date.new(2026, 10, 2), text: "Second")
    sign_in @owner
    get aircraft_logbook_entries_path(@a)
    assert_select "form#print-entries[action='#{new_aircraft_logbook_print_path(@a)}']"
    assert_select "input[type=checkbox][name='ids[]'][form=print-entries]", 2
    get new_aircraft_logbook_print_path(@a), params: { ids: [ @entry.id, other.id ] }
    assert_select "input[type=hidden][name='ids[]']", 2
    get new_aircraft_logbook_print_path(@a)
    assert_redirected_to aircraft_logbook_entries_path(@a)
    assert_equal "Choose the entries to print.", flash[:alert]

    elsewhere = create_aircraft(owner: create_user).logbook_entries.create!(date: Date.current, text: "Not yours")
    assert_includes text_of(pdf(ids: [ @entry.id, elsewhere.id ], layout: "letter")).then { refute_includes _1, "Not yours"; _1 }, "Sam Mechanic"

    sign_in create_user
    get aircraft_logbook_print_path(@a, format: :pdf), params: { ids: [ @entry.id ] }
    assert_response :not_found
  end
end
