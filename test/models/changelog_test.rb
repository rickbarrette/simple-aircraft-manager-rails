require "test_helper"

class ChangelogTest < ActiveSupport::TestCase
  SAMPLE = <<~MD
    # What's new

    The newest release is first.

    ## 2026.12.0

    ### Changes

    - One
    - Two
      - (a nested point, not counted)

    ### Fixes

    - A fix

    ## 2026.11.1

    ### For administrators

    - Set `TZ`

    ## 2026.11.0

    ### Flying

    - First
    - Second
  MD

  setup { @log = Changelog.new(SAMPLE) }

  test "splits the file into its title, intro and releases, newest first" do
    assert_equal "What's new", @log.title
    assert_equal "The newest release is first.", @log.intro
    assert_equal %w[2026.12.0 2026.11.1 2026.11.0], @log.releases.map(&:version)
    assert_equal Date.new(2026, 11, 1), @log.release("2026.11.1").month_start
    assert_equal "v2026-11-1", @log.release("2026.11.1").anchor
  end

  test "counts the top-level items under each section" do
    assert_equal({ changes: 2, fixes: 1 }, @log.release("2026.12.0").counts)
    assert_equal({ administrators: 1 }, @log.release("2026.11.1").counts)
    assert_equal({ notes: 2 }, @log.release("2026.11.0").counts) # other headings
  end

  test "the running version and newer are open; the newest when the running one has no notes" do
    assert_equal [ true, true, false ], @log.releases.map { @log.open?(_1, running: "2026.11.1") }
    assert_equal [ true, false, false ], @log.releases.map { @log.open?(_1, running: "unreleased") }
  end

  test "the real CHANGELOG.md parses, with notes for the current version" do
    log = Changelog.load
    assert log.releases.size >= 1
    assert log.release(SystemInfo.new.version), "CHANGELOG.md has no section for VERSION"
    log.releases.each { assert_predicate _1.counts.values.sum, :positive?, "#{_1.version} has no counted items" }
  end
end
