# A minimal iCalendar (RFC 5545) writer for all-day events.
class Ical
  def initialize(name)
    @name = name
    @events = []
  end

  def add(uid:, date:, summary:, description: nil, url: nil)
    @events << { uid: uid, date: date, summary: summary, description: description, url: url }
  end

  def to_s
    lines = [ "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Simple Aircraft Manager//EN", "CALSCALE:GREGORIAN",
              "METHOD:PUBLISH", "X-WR-CALNAME:#{escape(@name)}", "REFRESH-INTERVAL;VALUE=DURATION:PT6H", "X-PUBLISHED-TTL:PT6H" ]
    stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    @events.each do |e|
      lines += [ "BEGIN:VEVENT", "UID:#{e[:uid]}", "DTSTAMP:#{stamp}", "DTSTART;VALUE=DATE:#{e[:date].strftime('%Y%m%d')}",
                 "DTEND;VALUE=DATE:#{(e[:date] + 1).strftime('%Y%m%d')}", "SUMMARY:#{escape(e[:summary])}", "TRANSP:TRANSPARENT" ]
      lines << "DESCRIPTION:#{escape(e[:description])}" if e[:description].present?
      lines << "URL:#{e[:url]}" if e[:url].present?
      lines << "END:VEVENT"
    end
    lines << "END:VCALENDAR"
    lines.map { fold(_1) }.join("\r\n") + "\r\n"
  end

  private

  def escape(text) = text.to_s.gsub("\\", "\\\\\\\\").gsub(";", "\;").gsub(",", "\\,").gsub(/\r?\n/, "\\n")

  # Lines over 75 octets continue on the next line after a space.
  def fold(line)
    return line if line.bytesize <= 75
    parts = []
    current = +""
    line.each_char do |ch|
      if (current + ch).bytesize > (parts.empty? ? 75 : 74)
        parts << current
        current = +""
      end
      current << ch
    end
    parts << current
    parts.first + parts.drop(1).map { "\r\n #{_1}" }.join
  end
end
