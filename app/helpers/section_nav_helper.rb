# A page's sections, as the side list (shared/section_list) and the phone's
# sheet (shared/section_picker) both lay them out: under their group headings
# when the page gives them (`group:` on a section; only the long pages do),
# in the order the groups first appear, with anything dangerous set apart at
# the foot.
module SectionNavHelper
  # [[heading, sections], ...]: heading is a String, nil for sections with no
  # group, or :danger for the ones set apart at the foot.
  def section_groups(sections)
    danger, rest = sections.partition { |section| section[:danger] }
    groups = if rest.any? { |section| section[:group].present? }
      rest.group_by { |section| section[:group].presence }.to_a
    else
      [ [ nil, rest ] ]
    end
    groups << [ :danger, danger ] if danger.any?
    groups.reject { |_heading, items| items.empty? }
  end
end
