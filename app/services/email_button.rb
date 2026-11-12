# frozen_string_literal: true

# The one button an email may have (Tim, 2026-11-09: "if there's not an
# email button standard then there better be one"; six different hand-drawn
# buttons had piled up). It is the website's own primary button
# (shared/_button, "primary", medium): pink, white medium-weight text, 4px
# corners, the same padding. Email apps ignore stylesheets often enough that
# it has to be written on the link itself, so it is written here once.
#
# Three things keep it the only one:
#   - a view or a template writes its button with STYLE (or `html`), or
#     simply marks the link class="button";
#   - EmailButtonInterceptor runs `standardize` over every email as it
#     goes out, so a button drawn any other way still arrives as this one;
#   - spec/lib/email_button_spec.rb fails on a hand-drawn button in the code.
module EmailButton
  PINK = "#ec4899"
  STYLE = "display:inline-block;background-color:#{PINK};color:#ffffff;font-size:14px;font-weight:500;line-height:20px;" \
          "text-decoration:none;padding:10px 20px;border-radius:4px;"
  # An organization's own email to its mailing list wears the organization's
  # colour: the same button, on that colour. The link says so with
  # data-button-color, which `standardize` keeps.
  COLOR = /\A#\h{3,8}\z/
  OWN_COLOR = /\bdata-button-color\s*=\s*["'](#\h{3,8})["']/i

  STYLE_ATTRIBUTE = /\s*\bstyle\s*=\s*(?:"[^"]*"|'[^']*')/i

  module_function

  # The standard button on another background (see COLOR); pink for anything
  # that isn't a colour.
  def style(background: PINK)
    background.to_s.match?(COLOR) ? STYLE.sub(PINK, background.to_s) : STYLE
  end

  def html(text, url)
    %(<a href="#{ERB::Util.html_escape(url)}" class="button" style="#{STYLE}">#{ERB::Util.html_escape(text)}</a>)
  end

  # Every button in this HTML, made the standard one. Links that aren't
  # buttons are left exactly as they were.
  def standardize(html)
    return html if html.blank?

    html.gsub(/<a\b[^>]*>/im) { |tag| button?(tag) ? restyle(tag) : tag }
  end

  # A link is a button when it says so (class="button"), or when it was
  # drawn as one: a background and padding of its own.
  def button?(tag)
    return true if tag.match?(/\bclass\s*=\s*["'][^"']*\bbutton\b/i)

    style = tag[/\bstyle\s*=\s*"([^"]*)"/i, 1] || tag[/\bstyle\s*=\s*'([^']*)'/i, 1]
    style.to_s.match?(/background(-color)?\s*:/i) && style.to_s.match?(/padding/i)
  end

  def restyle(tag)
    tag.sub(STYLE_ATTRIBUTE, "").sub(/\s*>\z/, %( style="#{style(background: tag[OWN_COLOR, 1] || PINK)}">))
  end
end
