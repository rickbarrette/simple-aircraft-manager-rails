require "pdf-reader"

# Reads an oil analysis lab report PDF into sample records. Supported labs:
#   - Aviation Laboratories (AvLab): the current sample plus up to two previous
#     ones, each with its own verdict, comments and lab averages.
#   - Blackstone Laboratories: a grid of up to ~5 samples (newest first) with 20
#     elements, oil properties, and the lab's universal averages.
#
# Every sample comes back as a hash of OilAnalysis attributes plus :current.
class OilReportParser
  class Error < StandardError; end

  Report = Struct.new(:lab, :tail_number, :engine_serial, :engine_model, :oil_type, :samples, keyword_init: true)

  def self.from_pdf(io)
    reader = PDF::Reader.new(io)
    receivers = reader.pages.map { |page| PDF::Reader::PageTextReceiver.new.tap { page.walk(_1) } }
    text = receivers.flat_map { |r| r.runs(merge: true, skip_overlapping: false).map(&:text) }.join(" ")

    if text.match?(/blackstone-labs\.com|BLACKSTONE LABORATORIES/i)
      Blackstone.new(receivers.first.runs(merge: true, skip_overlapping: false)).parse
    elsif text.match?(/OIL ANALYSIS RESULTS IN PARTS PER MILLION|AVIATION LABORATORIES|avlab\.com/i)
      Avlab.from_receivers(receivers)
    else
      raise Error, I18n.t("services.oil_report.not_a_recognized_lab_report")
    end
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise Error, I18n.t("services.oil_report.couldn_t_read_the_pdf", message: e.message)
  end

  # "1,903" → 1903, "<0.5" → 0.5, "5 qts" → 5, ".3" → 0.3; nil for "-", "N/A"…
  def self.number(text)
    digits = text.to_s.delete(",").strip.sub(/\A[<>]\s*/, "")[/\A\d*\.?\d+/] or return nil
    BigDecimal(digits.sub(/\A\./, "0."))
  end

  # M/D/YYYY
  def self.date(text)
    Date.strptime(text, "%m/%d/%Y") if text
  rescue Date::Error
    nil
  end
end
