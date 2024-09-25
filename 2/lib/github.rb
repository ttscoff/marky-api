# frozen_string_literal: true

module Marky
  class GitHub
    def initialize(input = nil)
      @input = input
    end

    ## Shortcut for #new.process
    def self.process(input = nil)
      new(input).process
    end

    def self.processFile(input = nil)
      new(input).processFile
    end

    def self.processGist(input = nil)
      input ||= @input
      return nil if input.nil?

      output = []

      doc = Nokogiri::HTML(input)
      title = doc.css('h1').first.text.strip

      doc.css('svg').remove

      output << "<h1>#{title}</h1>"
      output << "<pre><code>"
      lines = doc.css("table.highlight td.js-file-line")

      lines.each do |line|
        output << line.text
      end

      output << "</pre></code>"

      output << '</div>'
      [output.join("\n"), title]
    end

    def processFile(input = nil)
      input ||= @input
      return nil if input.nil?

      output = []

      doc = Nokogiri::HTML(input)
      title = doc.css('title').text

      parts = title.match(%r{^[\w/]+/(.*?\.\w+) at \w+ \S+ (.*?) \S+ GitHub})

      title = "#{parts[2]}/#{parts[1]}" if parts
      doc.css('svg').remove

      output << "<h1>#{title}</h1>"
      output << "<pre><code>"
      lines = doc.css(".react-code-lines div.react-code-text")

      lines.each do |line|
        output << line.text
      end

      output << "</pre></code>"

      output << '</div>'
      [output.join("\n"), title]
    end

    def process(input = nil)
      input ||= @input
      return nil if input.nil?

      output = []
      output << '<div readability="100.00">'

      doc = Nokogiri::HTML(input)
      title = doc.css('title').text.sub('GitHub - ', '')
      doc.css('svg').remove

      output << "<h1>#{title}</h1>"

      output << doc.css('.markdown-body').inner_html

      output << '</div>'
      [output.join("\n"), title]
    end
  end
end
