require "test_helper"

class AirworthinessDirectiveTest < ActiveSupport::TestCase
  def ad(**attrs) = AirworthinessDirective.new({ name: "2011-10-09", short_description: "x" }.merge(attrs))

  test "stored link wins" do
    assert_equal [ "https://drs.faa.gov/x", "View AD" ], ad(document_url: "https://drs.faa.gov/x", docket_number: "FAA-2010-1101").reference_link
  end

  test "no guessed links: DRS document ids can't be derived from the AD number" do
    assert_nil ad(docket_number: "FAA-2010-1101").reference_link
  end

  test "only http(s) links are accepted" do
    assert_not ad(document_url: "javascript:alert(1)").valid?
    assert ad(document_url: " https://drs.faa.gov/x ").tap(&:valid?).document_url == "https://drs.faa.gov/x"
  end
end
