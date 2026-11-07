class OffsiteFile < ApplicationRecord
  belongs_to :blob, class_name: "ActiveStorage::Blob"
end
