require "test_helper"

class LogbookTemplateTest < ActiveSupport::TestCase
  test "every built-in template is valid and cites an existing Appendix A paragraph" do
    LogbookTemplate.defaults.each do |d|
      template = LogbookTemplate.new(d)
      assert template.valid?, "#{d['name']}: #{template.errors.full_messages.to_sentence}"
      # Part 43 Appendix A paragraph (c) runs from (1) to (31).
      d.values_at("reference", "text").join(" ").scan(/\(c\)\((\d+)\)/).flatten.each do |n|
        assert_includes 1..31, n.to_i, "#{d['name']} cites Appendix A (c)(#{n})"
      end
    end
  end

  test "the tray-mounted nav/com swap cites (c)(31)" do
    LogbookTemplate.restore_defaults!
    swap = LogbookTemplate.find_by!(name: "Swapping a tray-mounted nav/com unit")
    assert_equal "Part 43 App. A (c)(31)", swap.reference
    assert_includes swap.text, "paragraph (c)(31)"
    assert_equal "PILOT", swap.certificate_type
  end

  test "a navigation database update is recorded as a note, not preventive maintenance" do
    LogbookTemplate.restore_defaults!
    update = LogbookTemplate.find_by!(name: "Updating the navigation database")
    assert_equal "14 CFR 43.3(k)", update.reference
    assert_equal "OTHER", update.entry_type
    assert_nil update.certificate_type
    assert_not_includes update.text, "Preventive maintenance"
  end
end
