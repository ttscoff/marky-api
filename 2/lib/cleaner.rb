# frozen_string_literal: true

require_relative "tablecleanup"

class ::String
  ##
  ## Use nokogiri to convert tables
  ##
  ## @return     Content with tables markdownified
  ##
  def fix_tables
    gsub(%r{<table.*?>.*?</table>}m) do
      m = Regexp.last_match
      HTML2Markdown.new(m[0]).to_s.fix_indentation
    end.gsub(/\|\n\[/, "|\n\n[")
  end

  ##
  ## Make indentation of subsequent lines match the first line
  ##
  ## @return     [String] Outdented version of text
  ##
  def fix_indentation
    return self unless strip =~ (/^\s+\S/)

    out = []
    lines = split(/\n/)
    lines.delete_if { |l| l.strip.empty? }
    indent = lines[0].match(/^(\s*)\S/)[1]
    indent ||= ""

    lines.each do |line|
      next if line.strip.empty?

      out << line.sub(/^\s*/, indent)
    end

    "\n#{out.join("\n")}\n"
  end

  def remove_tag(tag, preserve_contents = true)
    gsub(%r{<#{tag}[^>]*>(.*?)</#{tag}>}m, preserve_contents ? "\\1" : "")
  end

  def remove_tag!(tag, preserve_contents = true)
    replace remove_tag(tag, preserve_contents)
  end
end

class MarkdownCleaner
  def initialize(input)
    @input = input
  end

  def clean
    input = @input

    # remove script and style tags

    input.remove_tag!("script", false)
    input.remove_tag!("style", false)

    # input = `echo #{Shellwords.escape(input)} | pandoc -f html -t gfm --wrap=none`

    # Remove non-breaking spaces
    input.gsub!(/&nbsp;/, " ")
    input.gsub!(/\u00A0/, " ")

    # Fix broken headers
    input.gsub!(/^(#+)\s*\n+(\S)/, "\\1 \\2")

    # # Fix line breaks
    input.gsub!(/<br[^>]*>/, "  \n")

    # Fix links containing spaces
    input.gsub!(/\[ *(.*?) *\]([\[(])/, '[\1]\2')

    # image cleanup
    input.gsub!(/<img(.*?)src="([^"]+)"([^>]*)>/m) do
      m = Regexp.last_match
      src = m[2]
      alt = ""
      title = ""

      attrs = "#{m[1]} #{m[3]}"
      # look for alt attribute
      if attrs =~ /alt="(.*?)"/
        alt = $1
      end

      # look for data-*-src attribute
      if attrs =~ /data.*?src="(.*?)"/
        src = $1
      end

      # look for title attribute
      if attrs =~ /title="(.*?)"/
        title = %( "#{$1}")
      end

      "![#{alt}](#{src}#{title})"
    end

    # List item cleanup
    input.gsub!(/^([ \t]*)([-*+]) +/, '\1\2 ')

    # code block cleanup
    # input.gsub!(/<pre(.*?)><code(.*?)>(.+?)<\/code><\/pre>/m) do
    #   m = Regexp.last_match
    #   attrs = "#{m[1]} #{m[2]}"
    #   lang = ""
    #   if attrs =~ /class="(.*?)"/
    #     lang = $1.split(/ +/).last
    #   end
    #   "\n\n```#{lang.strip}\n#{m[3]}\n```\n\n"
    # end
    # clean newlines around fenced code
    input.gsub!(/(([ \t]*(`{3,}))[^\n`]*)(\n+.*?)(\2)/) do
      m = Regexp.last_match
      "#{m[1]}\n#{m[4].strip}\n#{m[5]}"
    end

    input.gsub!(/(\S)```(\S)/) do
      m = Regexp.last_match
      "#{m[1]}\n```\n\n#{m[2]}"
    end

    input.gsub!(/(\S+)\s*```/, "\\1\n```")
    input.gsub!(/``` \S+ (.*?)/, "```\n\\1")
    input.gsub!(/``` \S+\n/, "```\n")

    input.gsub!(/<code(.*?)>(.+?)<\/code>/m) do
      m = Regexp.last_match
      " `#{m[2]}` "
    end

    # paragraph cleanup
    input.gsub!(/<p>(.*?)<\/p>/m, "\n\\1\n")

    # symbol cleanup
    input = HTMLEntities.new.decode input

    # link cleanup
    input.gsub!(%r{<a.*?href="([^"]+)"[^>]*>(.*?)</a>}m) do
      m = Regexp.last_match
      "[#{m[2]}](#{m[1]})"
    end

    # Table cleanup
    input = input.fix_tables
    # input.gsub!(/^.*?(\|.*?)+\n([|: \-]+)+\n((\s*\|?.*?\|)+.*?\n)+/) do |match|
    #   table = `echo #{Shellwords.escape(match)}|lib/clean_tables.pl`
    #   "\n#{table}\n"
    # end

    tc = TableCleanup.new(input)
    tc.max_cell_width = 80
    tc.max_table_width = 150
    input = tc.clean

    # remove empty links
    input.gsub!(/\[([^\]]+)\]\(\s*\)/, '\1')
    input.gsub!(/([^!]|\A)\[\s*\]\(.*?\)/, "")

    # tag cleanup
    input.gsub!(%r{</?(div|section|aside|span|figure)[^>]*?>}m, "")

    # Whitespace cleanup
    # list cleanup only matches list items at first level (for now)
    input.gsub!(/^([*+-])[\n\s]*((  (\S.*?)[\n\s]+)+)$/) do
      m = Regexp.last_match
      content = m[2].gsub(/(^  \n)+/, "\n\n").gsub(/^  /, "    ").strip
      "#{m[1]} #{content}\n"
    end
    # Fix list items where content is on the next line and list item is empty
    input.gsub!(/([\*\-\+] .*?)\n+(?=[\*\-\+] )/, "\\1\n")
    input.gsub!(/\n{2,}/m, "\n\n")

    # Clean excess empty lines in block quotes
    # Retains one spacer > line within block quotes
    input.gsub!(/(^>\s*?\n)+/, ">\n")

    # Remove empty headers
    input.gsub!(/^#+ *\n/, "")

    # Clean multiple newlines
    input.gsub!(/(^\s*\n){3,}/, "\n\n")

    # # Replace temp br tags
    # input.gsub!(/__BR__/, "  \n")

    input.strip
  end
end
