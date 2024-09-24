#!/usr/bin/env ruby

require "cgi"

cgi = CGI.new

puts cgi.header
puts "<html><body>"
puts "<h1>Query String</h1>"
puts "<p>#{cgi.query_string}</p>"
puts "<h1>Params</h1>"
puts "<ul>"
cgi.params.each do |key, value|
  puts "<li>#{key}: #{value}</li>"
end
puts "</ul>"
puts "</body></html>"
