require "test_helper"

# The user guide in docs/guide, shown under /help.
class UserGuideTest < ActionDispatch::IntegrationTest
  setup { sign_in create_user("pilot@example.com") }

  test "every guide page renders with the contents and links between pages" do
    get help_path
    assert_response :success
    assert_select "h1", "User guide"
    HelpGuide::ORDER.each do |slug|
      assert HelpGuide.find(slug), "docs/guide/#{slug}.md is missing"
      get(slug == "README" ? help_path : help_page_path(slug))
      assert_response :success
      assert_select "nav[aria-label='Help pages'] a", HelpGuide::ORDER.size * 2
      assert_no_match(/href="[a-z-]+\.md/, response.body, "#{slug} has an unconverted .md link")
    end
    get help_page_path("logbook")
    assert_select "a[href='/help/records#mistakes']"
  end

  test "links in the guide point at real pages and headings" do
    HelpGuide.pages.each do |page|
      page.markdown.scan(/\]\(([a-z-]+|README)\.md(?:#([a-z0-9-]+))?\)/).each do |slug, anchor|
        target = HelpGuide.find(slug)
        assert target, "#{page.slug} links to missing #{slug}.md"
        assert_includes HelpGuide.html(target, link: nil), %(id="#{anchor}"), "#{page.slug} links to missing ##{anchor} in #{slug}" if anchor
      end
    end
  end

  test "only guide pages can be opened" do
    get "/help/secrets"
    assert_response :not_found
    get records_help_path
    assert_response :success
    assert_includes response.body, "Correct this entry"
  end

  test "the guide is in the menu" do
    get root_path
    assert_select "a[href='/help']", minimum: 1
  end
end
