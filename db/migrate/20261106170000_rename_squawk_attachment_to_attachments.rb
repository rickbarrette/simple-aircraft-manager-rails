# Squawks go from one attachment to many; keep the files already uploaded.
class RenameSquawkAttachmentToAttachments < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE active_storage_attachments SET name = 'attachments' WHERE record_type = 'Squawk' AND name = 'attachment'"
  end

  def down
    # Only the first file per squawk fits back into a single attachment.
    execute <<~SQL
      DELETE FROM active_storage_attachments
      WHERE record_type = 'Squawk' AND name = 'attachments'
        AND id NOT IN (SELECT MIN(id) FROM active_storage_attachments WHERE record_type = 'Squawk' AND name = 'attachments' GROUP BY record_id)
    SQL
    execute "UPDATE active_storage_attachments SET name = 'attachment' WHERE record_type = 'Squawk' AND name = 'attachments'"
  end
end
