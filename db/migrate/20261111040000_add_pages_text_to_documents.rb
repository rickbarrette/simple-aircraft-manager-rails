class AddPagesTextToDocuments < ActiveRecord::Migration[8.1]
  def change
    # Text read from the document's pages, for search (derived, not a record).
    add_column :documents, :pages_text, :text
    add_column :documents, :pages_text_method, :string # text | ocr | claude | none
    add_column :documents, :pages_text_source, :string # the page files it was read from
    add_column :documents, :pages_text_at, :datetime
  end
end
