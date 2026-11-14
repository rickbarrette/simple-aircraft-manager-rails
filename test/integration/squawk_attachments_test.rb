require "test_helper"

class SquawkAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot)
  end

  def upload(name, type = "text/plain", body = "file #{name}")
    Rack::Test::UploadedFile.new(StringIO.new(body), type, original_filename: name)
  end

  test "a pilot can report a squawk with several files" do
    sign_in @pilot
    post aircraft_squawks_path(@a), params: { squawk: { priority: 1, issue_reported: "Cracked fairing",
                                                        attachments: [ "", upload("front.jpg", "image/jpeg"), upload("notes.txt") ] } }
    squawk = @a.squawks.last
    assert_equal %w[front.jpg notes.txt], squawk.attachments.map { _1.filename.to_s }.sort

    get aircraft_squawks_path(@a)
    assert_select "[data-controller=gallery]" do
      assert_select "a[data-gallery-target=item][data-action='gallery#open'][href*='front.jpg'] img[alt='front.jpg'][loading=lazy][src*='/representations/']"
      assert_select "a[data-gallery-target=item]", 1 # only photos open in the viewer
      assert_select "a[target=_blank][href*='notes.txt']", text: /📎/
      assert_select "dialog[data-gallery-target=dialog] a[data-gallery-target=download]"
    end
  end

  test "every file can be downloaded: other files from their link, photos from the viewer" do
    @a.squawks.create!(priority: 1, issue_reported: "x", attachments: [ upload("pic.png", "image/png", png), upload("log.pdf", "application/pdf") ])
    sign_in @pilot
    get aircraft_squawks_path(@a)
    downloads = css_select("a[download]").reject { _1["data-gallery-target"] }.map { _1["href"] }
    downloads << css_select("a[data-gallery-target=item]").sole["data-gallery-download"]
    assert_equal 2, downloads.size
    downloads.each do |href|
      get href
      follow_redirect! while response.redirect?
      assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
    end
  end

  test "photo thumbnails are small resized copies" do
    @a.squawks.create!(priority: 1, issue_reported: "x", attachments: [ upload("pic.png", "image/png", png) ])
    sign_in @pilot
    get aircraft_squawks_path(@a)
    get css_select("a[data-gallery-target=item] img").sole["src"]
    follow_redirect! while response.redirect?
    assert_response :success
    assert_equal [ 160, 160 ], Vips::Image.new_from_buffer(response.body, "").then { [ _1.width, _1.height ] }
  end

  # A 200 × 120 PNG (made when first needed: libvips must not start before the test processes fork).
  def png = @png ||= Vips::Image.black(200, 120).write_to_buffer(".png")

  test "squawks with no photos get no viewer" do
    @a.squawks.create!(priority: 1, issue_reported: "x", attachments: [ upload("notes.txt") ])
    sign_in @pilot
    get aircraft_squawks_path(@a)
    assert_select "dialog", 0
    assert_select "a[download='notes.txt']"
  end

  test "an owner can add files and remove some in one edit" do
    squawk = @a.squawks.create!(priority: 1, issue_reported: "Oil leak", attachments: [ upload("a.txt"), upload("b.txt") ])
    a_file = squawk.attachments.find { _1.filename.to_s == "a.txt" }
    sign_in @owner

    get edit_aircraft_squawk_path(@a, squawk)
    assert_select "input[type=file][multiple][name='squawk[attachments][]']"
    assert_select "input[type=checkbox][name='remove_attachment_ids[]']", 2

    patch aircraft_squawk_path(@a, squawk), params: { squawk: { issue_reported: "Oil leak at sump", attachments: [ "", upload("c.txt") ] },
                                                      remove_attachment_ids: [ a_file.id ] }
    assert_redirected_to aircraft_squawks_path(@a)
    squawk.reload
    assert_equal "Oil leak at sump", squawk.issue_reported
    assert_equal %w[b.txt c.txt], squawk.attachments.map { _1.filename.to_s }.sort
  end

  test "editing without touching files keeps them" do
    squawk = @a.squawks.create!(priority: 1, issue_reported: "x", attachments: [ upload("a.txt") ])
    sign_in @owner
    patch aircraft_squawk_path(@a, squawk), params: { squawk: { notes: "Ordered part", attachments: [ "" ] } }
    assert_equal %w[a.txt], squawk.reload.attachments.map { _1.filename.to_s }
  end

  test "a bad file rejects the whole edit and removes nothing" do
    squawk = @a.squawks.create!(priority: 1, issue_reported: "Oil leak", attachments: [ upload("a.txt") ])
    sign_in @owner
    patch aircraft_squawk_path(@a, squawk), params: { squawk: { issue_reported: "Changed", attachments: [ upload("run.exe", "application/x-msdownload") ] },
                                                      remove_attachment_ids: [ squawk.attachments.first.id ] }
    assert_response :unprocessable_entity
    assert_match "run.exe is not an allowed file type", response.body
    squawk.reload
    assert_equal "Oil leak", squawk.issue_reported
    assert_equal %w[a.txt], squawk.attachments.map { _1.filename.to_s }
  end

  test "pilots can't edit a squawk's files" do
    squawk = @a.squawks.create!(priority: 1, issue_reported: "x", attachments: [ upload("a.txt") ])
    sign_in @pilot
    patch aircraft_squawk_path(@a, squawk), params: { remove_attachment_ids: [ squawk.attachments.first.id ], squawk: { notes: "y" } }
    assert_equal 1, squawk.reload.attachments.count
  end
end
