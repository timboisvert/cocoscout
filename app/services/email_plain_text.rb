# frozen_string_literal: true

# An email's HTML as readable plain text: the body only (no <head> or
# styles), paragraphs and rows on their own lines, list items as "- ",
# table cells spaced apart, and links written out ("View your tickets
# (https://…)") since a text email can't hide a URL behind words.
module EmailPlainText
  module_function

  def from_html(html)
    text = html.to_s.dup
    text = text[%r{<body[^>]*>(.*)</body>}mi, 1] || text
    text = text.gsub(%r{<(style|script|head)[^>]*>.*?</\1>}mi, "")
    text = text.gsub(%r{<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>}mi) do
      href = Regexp.last_match(1)
      words = strip(Regexp.last_match(2)).strip
      next words if href.start_with?("cid:", "#") || words.empty?

      href = CGI.unescapeHTML(href)
      words == href || href.start_with?("mailto:#{words}") ? words : "#{words} (#{href})"
    end
    text = text.gsub(%r{<br\s*/?>}i, "\n")
               .gsub(%r{<li[^>]*>}i, "\n- ")
               .gsub(%r{</(td|th)>}i, "   ")
               .gsub(%r{</(p|div|h[1-6]|tr|table|ul|ol|blockquote)>}i, "\n\n")
    # Every entity (&nbsp;, &rsquo;, &mdash;…), not just the five basic ones.
    text = Nokogiri::HTML::DocumentFragment.parse(strip(text)).text
    text.gsub(" ", " ")
        .split("\n").map { |line| line.gsub(/[ \t]+/, " ").strip }.join("\n")
        .gsub(/\n{3,}/, "\n\n").strip
  end

  def strip(fragment)
    fragment.gsub(/<[^>]+>/, "")
  end
end
