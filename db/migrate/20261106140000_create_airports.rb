# Airport reference data (OurAirports, the source AirTrail uses) for
# autocomplete and for translating codes to AirTrail's. The data itself is
# downloaded on first start (AirportUpdateJob), as AirTrail does.
class CreateAirports < ActiveRecord::Migration[8.1]
  def up
    create_table :airports do |t|
      t.string :ident, null: false
      t.string :airtrail_code, null: false
      t.string :gps_code
      t.string :local_code
      t.string :iata
      t.string :name, null: false
      t.string :kind
      t.string :municipality
      t.string :region
      t.string :country
      t.float :latitude
      t.float :longitude
      t.integer :elevation_ft
      t.timestamps
    end
    add_index :airports, :ident, unique: true
    add_index :airports, :airtrail_code
    add_index :airports, :gps_code
    add_index :airports, :local_code
    add_index :airports, :iata
  end

  def down
    drop_table :airports
  end
end
