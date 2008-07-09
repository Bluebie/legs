Gem::Specification.new do |s|
  s.name = "legs"
  s.version = "0.5"
  s.date = "2008-07-09"
  s.summary = "Simple fun open networking for newbies and quick hacks"
  s.email = "blue@creativepony.com"
  s.homepage = "http://github.com/Bluebie/legs"
  s.description = "Legs is a really simple fun networking library that uses 'json-rpc' formated messages over a tcp connection to really easily built peery or server-clienty sorts of apps, for ruby newbies and hackers to build fun little things."
  s.has_rdoc = false
  s.authors = ["Jenna 'Bluebie' Fox"]
  s.files = ["README.rdoc", "legs.gemspec", "lib/legs.rb", "examples/echo-server.rb", "examples/chat-server.rb", "examples/shoes-chat-client.rb", "test/tester.rb"]
  s.add_dependency("json_pure", ["> 1.1.0"])
end