# A life-limited part that's cleaned and reused (e.g. a Challenger oil filter):
# its "replace every" limit counts from when it was installed (total time in
# service), not from its last service.
class AddReplacementFromInstallToComponents < ActiveRecord::Migration[8.1]
  def change
    add_column :components, :replacement_from_install, :boolean, default: false, null: false
  end
end
