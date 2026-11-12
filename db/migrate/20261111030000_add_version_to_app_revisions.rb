class AddVersionToAppRevisions < ActiveRecord::Migration[8.1]
  def change
    # The release version (YYYY.MM.N) that build was, next to its commit.
    add_column :app_revisions, :version, :string
  end
end
