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
