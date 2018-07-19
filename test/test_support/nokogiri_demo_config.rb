settings do
  provide "nokogiri.namespaces",  {
    "oai" => "http://www.openarchives.org/OAI/2.0/",
    "dc" => "http://purl.org/dc/elements/1.1/",
    "oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/"
  }
end

to_field "institution", literal("University of Hogwarts")

to_field "id", extract_xpath("//oai:record//oai:metadata/oai_dc:dc/dc:identifier"), first_only
to_field "title", extract_xpath("//oai:metadata/oai_dc:dc/dc:title")
to_field "rights", extract_xpath("//oai:metadata/oai_dc:dc/dc:rights")
to_field "creator", extract_xpath("//oai:metadata/oai_dc:dc/dc:creator")
to_field "description", extract_xpath("//oai:metadata/oai_dc:dc/dc:description")
to_field "creator", extract_xpath("//oai:metadata/oai_dc:dc/dc:format")

