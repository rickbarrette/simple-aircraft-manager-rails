# Inspection rules closer to Part 91:
# - effect: what an overdue inspection means (grounded, no IFR per 91.411,
#   no transponder per 91.413, or advisory)
# - satisfies: completing this type also counts as another (an annual
#   satisfies the 100-hour, 91.409(b))
# - hours_tolerance: allowed overrun whose excess counts toward the next
#   interval (the 100-hour's 10 hours, 91.409(b))
# - aircraft.time_basis: which clock is time in service for maintenance
class AddRegulatoryInspectionRules < ActiveRecord::Migration[8.1]
  def up
    add_column :inspection_types, :effect, :string, null: false, default: "grounds"
    add_column :inspection_types, :hours_tolerance, :decimal, precision: 6, scale: 1, null: false, default: 0
    add_reference :inspection_types, :satisfies, foreign_key: { to_table: :inspection_types, on_delete: :nullify }
    add_column :aircraft, :time_basis, :string, null: false, default: "tach"

    execute "UPDATE inspection_types SET effect = 'advisory' WHERE required = 0"
    execute <<~SQL
      UPDATE inspection_types SET effect = 'no_transponder'
      WHERE required = 1 AND (LOWER(name) LIKE '%transponder%' OR name LIKE '%91.413%')
    SQL
    execute <<~SQL
      UPDATE inspection_types SET effect = 'no_ifr'
      WHERE required = 1 AND (LOWER(name) LIKE '%pitot%' OR LOWER(name) LIKE '%static%'
                              OR LOWER(name) LIKE '%altimeter%' OR name LIKE '%91.411%')
    SQL
    hundred = "(LOWER(name) LIKE '%100%hour%' OR LOWER(name) LIKE '%100%hr%')"
    execute "UPDATE inspection_types SET hours_tolerance = 10 WHERE #{hundred}"

    # Link annual → 100-hour only when there's exactly one of each to link.
    annuals = select_values("SELECT id FROM inspection_types WHERE LOWER(name) LIKE '%annual%'")
    hundreds = select_values("SELECT id FROM inspection_types WHERE #{hundred}")
    if annuals.size == 1 && hundreds.size == 1 && annuals != hundreds
      execute "UPDATE inspection_types SET satisfies_id = #{hundreds.first.to_i} WHERE id = #{annuals.first.to_i}"
    end
  end

  def down
    remove_reference :inspection_types, :satisfies, foreign_key: { to_table: :inspection_types }
    remove_column :inspection_types, :hours_tolerance
    remove_column :inspection_types, :effect
    remove_column :aircraft, :time_basis
  end
end
