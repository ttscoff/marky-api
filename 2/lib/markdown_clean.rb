#!/usr/bin/env ruby
require "shellwords"
require_relative "htmlentities/htmlentities.rb"
require_relative "html2markdown.rb"
require "nokogiri"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
input = $stdin.read.force_encoding("utf-8")

# frozen_string_literal: true

# Table formatting, cleans up tables in content
# @api public
class TableCleanup
  # Max cell width for formatting, defaults to 30
  attr_writer :max_cell_width
  # Max table width for formatting, defaults to 60
  attr_writer :max_table_width
  # The content to process
  attr_writer :content

  ##
  ## Initialize a table cleaner
  ##
  ## @param      content  [String] The content to clean
  ## @param      options  [Hash] The options
  ##
  def initialize(content = nil, options = nil)
    @content = content ? content : ""
    @max_cell_width = options && options[:max_cell_width] ? options[:max_cell_width] : 30
    @max_table_width = options && options[:max_table_width] ? options[:max_table_width] : nil
  end

  ##
  ## Split a row string on pipes
  ##
  ## @param      row   [String] The row string
  ##
  ## @return [Array] array of cell strings
  ##
  def parse_cells(row)
    row.split("|").map(&:strip)[1..-1]
  end

  ##
  ## Builds a formatted table
  ##
  ## @param      table [Array<Array>]   The table, an array of row arrays
  ##
  ## @return [String] the formatted table
  ##
  def build_table(table)
    @widths = [0] * table.first.size

    table.each do |row|
      row.each_with_index do |cell, col|
        if @widths[col]
          @widths[col] = cell.size if @widths[col] < cell.size
        else
          @widths[col] = cell.size
        end
      end
    end

    @string = ''

    first_row = table.shift
    render_row first_row
    render_alignment

    table.each do |row|
      render_row row
    end

    @string
  end

  ##
  ## Align content withing cell based on header alignments
  ##
  ## @param      string     [String] The string to align
  ## @param      width      [Integer] The cell width
  ##
  ## @return [String] aligned string
  ##
  def align(alignment, string, width)
    case alignment
    when :left
      string.ljust(width, " ")
    when :right
      string.rjust(width, " ")
    when :center
      string.center(width, " ")
    end
  end

  ##
  ## Render a row
  ##
  ## @param      row     [Array] The row of cell contents
  ##
  ## @return [String] the formatted row
  ##
  def render_row(row)
    idx = 0
    @max_cell_width = @max_table_width / row.count if @max_table_width

    @string << "|"
    row.zip(@widths).each do |cell, width|
      width = @max_cell_width - 2 if width >= @max_cell_width
      if width.zero?
        @string << "|"
      else
        content = @alignment ? align(@alignment[idx], cell, width) : cell.ljust(width, " ")
        @string << " #{content} |"
      end
      idx += 1
    end
    @string << "\n"
  end

  ##
  ## Render the alignment row
  ##
  def render_alignment
    @string << "|"
    @alignment.zip(@widths).each do |align, width|
      @string << ":" if align == :left
      width = @max_cell_width - 2 if width >= @max_cell_width
      @string << "-" * (width + (align == :center ? 2 : 1))
      @string << ":" if align == :right
      @string << "|"
    end
    @string << "\n"
  end

  ##
  ## String helpers
  ##
  class ::String
    ##
    ## Ensure leading and trailing pipes
    ##
    ## @return     [String] string with pipes
    ##
    def ensure_pipes
      strip.gsub(/^\|?(.*?)\|?$/, '|\1|')
    end

    def alignment?
      self =~ /^[\s|:-]+$/ ? true : false
    end
  end

  ##
  ## Clean tables within content
  ##
  def clean
    table_rx = /^(?ix)(?<table>
    (?<header>\|?(?:.*?\|)+.*?)\s*\n
    ((?<align>\|?(?:[:-]+\|)+[:-]*)\s*\n)?
    (?<rows>(?:\|?(?:.*?\|)+.*?(?:\n|\Z))+))/

    @content.gsub!(/(\|?(?:.+?\|)+)\n\|\n/) do
      m = Regexp.last_match
      cells = parse_cells(m[1]).count
      "#{m[1]}\n#{"|" * cells}\n"
    end

    tables = @content.to_enum(:scan, table_rx).map { Regexp.last_match }

    tables.each do |t|
      table = []

      if t["align"].nil?
        cells = parse_cells(t["header"])
        align = "|#{([":---"] * cells.count).join("|")}|"
      else
        align = t["align"]
      end

      @alignment = parse_cells(align.ensure_pipes).map do |cell|
        if cell[0, 1] == ":" && cell[-1, 1] == ":"
          :center
        elsif cell[-1, 1] == ":"
          :right
        else
          :left
        end
      end

      lines = t["table"].split(/\n/)
      lines.delete_if(&:alignment?)

      lines.each do |row|
        # Ensure leading and trailing pipes
        row = row.ensure_pipes

        cells = parse_cells(row)

        table << cells
      end

      @content.sub!(/#{Regexp.escape(t["table"])}/, "#{build_table(table)}\n")
    end

    @content
  end
end

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
end

module Marky
  class MarkdownCleanup
    def initialize(content)
      puts content
      puts "made it"
      Process.exit 0
      @content = content
    end

    def clean
      clean_markdown(@content)
    end

    private

    def clean_markdown(input)
      # remove script and style tags
      input.gsub!(%r{<script.*?>.*?</script>}m, "")
      input.gsub!(%r{<style.*?>.*?</style>}m, "")

      # input = `echo #{Shellwords.escape(input)} | pandoc -f html -t gfm --wrap=none`

      # # Fix line breaks
      input.gsub!(/<br[^>]*>/, "  \n")

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

      # code block cleanup
      input.gsub!(/<pre(.*?)><code(.*?)>(.+?)<\/code><\/pre>/m) do
        m = Regexp.last_match
        attrs = "#{m[1]} #{m[2]}"
        lang = ""
        if attrs =~ /class="(.*?)"/
          lang = $1.split(/ +/).last
        end
        "\n\n```#{lang.strip}\n#{m[3]}\n```\n\n"
      end

      input.gsub!(/(\S)```(\S)/) do
        m = Regexp.last_match
        "#{m[1]}\n```\n\n#{m[2]}"
      end

      input.gsub!(/(\S+)\s*```/, "\\1\n\n```")
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
      tc.max_cell_width = 20
      tc.max_table_width = 80
      input = tc.clean

      # remove empty links
      input.gsub!(/\[([^\]]+)\]\(\s*\)/, '\1')
      input.gsub!(/([^!]|\A)\[\s*\]\(.*?\)/, "")

      # code cleanup
      input.gsub!(%r{</?(div|section|aside|span|figure)[^>]*?>}m, "")

      # Whitespace cleanup
      input.gsub!(/^([*+-])[\n\s]*((  (\S.*?)[\n\s]+)+)$/) do
        m = Regexp.last_match
        content = m[2].gsub(/\n+/, "\n\n").gsub(/^  /, "    ").strip
        "#{m[1]} #{content}\n"
      end
      input.gsub!(/([\*\-\+] .*?)\n+(?=[\*\-\+] )/, "\\1\n")
      input.gsub!(/\n{2,}/m, "\n\n")

      # # Replace temp br tags
      # input.gsub!(/__BR__/, "  \n")

      puts input
    end
  end
end
