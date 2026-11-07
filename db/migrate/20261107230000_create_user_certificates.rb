class CreateUserCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :user_certificates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :number, null: false
      t.date :expires_on
      t.timestamps
    end
  end
end
