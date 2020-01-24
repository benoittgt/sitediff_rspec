require 'nokogiri'
require 'open-uri'

DOC_CURRENT_VERSION = "http://rspec.info/documentation/3.9"
DOC_NEW_VERSION = "http://0.0.0.0:4567/documentation/3.9"

PAGE_LIST = [
  "rspec-rails/RSpec/Rails"
]

CLASS_NODES_TO_REMOVE = [
  "defines",
  "summary_signature",
  "signature"
]

ID_NODES_TO_REMOVE = [
  "Assertions-constant"
]

def get_html(base_url: , page_link:)
  puts ">> Get html for: #{base_url}/#{page_link}.html"
  Nokogiri::HTML(URI.open("#{base_url}/#{page_link}.html"))
end

def extract_text(html)
  text = []
  html.at_css("div#content").traverse do |node|
    if CLASS_NODES_TO_REMOVE.include?(node.attr('class')) ||
        ID_NODES_TO_REMOVE.include?(node.attr('id')) ||
        node.text =~ /collapse|\+ \(Object\)| ⇒ Object /
      puts <<-NOTICE
       Ignoring:
         node.name: #{node.name}
         class: #{node.attr('class')}
         id: #{node.attr('id')}
         text: \n--------------\n#{node.text}\n--------------
       NOTICE
      node.remove
      next
    end
    text << node.text
  end
  text.join('')
end

class String
  def to_filename
    "export/#{tr("/", "-")}"
  end
end

PAGE_LIST.each do |page_link|
  current_web_page_file_name = page_link.to_filename + ".current"
  new_web_page_file_name = page_link.to_filename + ".new"

  File.write(
    current_web_page_file_name,
    extract_text(get_html(base_url: DOC_CURRENT_VERSION, page_link: page_link))
  )

  File.write(
    new_web_page_file_name,
    extract_text(get_html(base_url: DOC_NEW_VERSION, page_link: page_link))
  )

  system(
    <<~SHELL
     git diff \
       --no-index \
       --ignore-all-space \
       --ignore-blank-lines \
       --minimal \
       #{current_web_page_file_name} #{new_web_page_file_name} > #{page_link.to_filename}.diff
     SHELL
  )
  puts ">> Diff done: #{page_link.to_filename}.diff"
end


