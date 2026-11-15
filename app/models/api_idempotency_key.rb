# A write sent with an Idempotency-Key header, and the answer it got: the
# same key again (a retry) gets the same answer instead of a second record.
class ApiIdempotencyKey < ApplicationRecord
  KEEP_FOR = 24.hours

  belongs_to :api_token

  def self.purge_old = where(created_at: ...KEEP_FOR.ago).delete_all
end
