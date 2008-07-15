# Makes use of ZenTest. Install the 'ZenTest' gem, then run this ruby script in a terminal to see the results!
require 'test/unit' unless defined? $ZENTEST and $ZENTEST
require '../lib/legs'

# want to see errors, don't want to see excessively verbose logging normally
Thread.abort_on_exception = true
#Legs.log = true

# class to test the marshaling
class MarshalTesterClass; attr_accessor :a, :b, :c; end

# a simple server to test with
Legs.start(6425) do
  def echo(text)
    return text
  end
  
  def count
    caller.meta[:counter] ||= 0
    caller.meta[:counter] += 1
  end
  
  def methods
    'overridden'
  end
  
  def error
    raise "This is a fake error"
  end
  
  def notified
    $notified = true
  end
  
  def marshal
    obj = MarshalTesterClass.new
    obj.a = 1; obj.b = 2; obj.c = 3
    return obj
  end
  
  def on_connect
    $server_instance = caller
  end
  
  def on_some_event
    $some_event_ran = true
  end
end

Remote = Legs.new('localhost', 6425)


class TestLegsObject < Test::Unit::TestCase
  def test_class_broadcast
    $notified = false
    Legs.broadcast(:notified)
    sleep 0.5
    assert_equal(true, $notified)
  end

  def test_class_connections
    assert_equal(2, Legs.connections.length)
  end

  def test_class_event
    Legs.event :some_event, nil
    sleep 0.1
    assert_equal(true, $some_event_ran)
  end

  def test_class_find_user_by_object_id
    assert_equal(Legs.incoming.first, Legs.find_user_by_object_id(Legs.incoming.first.object_id))
  end

  def test_class_find_users_by_meta
    Legs.incoming.first.meta[:id] = 'This is the incoming legs instance'
    assert_equal(true, Legs.find_users_by_meta(:id => /incoming legs/).include?(Legs.incoming.first))
  end

  def test_class_incoming
    assert_equal(true, Legs.incoming.length > 0)
  end

  def test_class_outgoing
    assert_equal(Legs.outgoing.class, Array)
    assert_equal(Legs.outgoing.length, 1)
  end
  
  def test_class_open
    instance = nil
    Legs.open('localhost', 6425) do |i|
      instance = i
    end
    assert_equal(Legs, instance.class)
  end

  def test_class_started_eh
    assert_equal(Legs.started?, true)
  end

  def test_connected_eh
    assert_equal(Remote.connected?, true)
  end

  def test_close_bang
    ii = Legs.new('localhost', 6425)
    assert_equal(Legs.outgoing.length, 2)
    ii.close!
    assert_equal(Legs.outgoing.length, 1)
  end

  def test_meta
    assert_equal(true, Remote.meta.is_a?(Hash))
    Remote.meta[:yada] = "Yada"
    assert_equal("Yada", Remote.meta[:yada])
  end

  def test_notify_bang
    $notified = false
    Remote.notify! :notified
    sleep(0.2)
    assert_equal($notified, true)
  end

  def test_parent
    assert_equal(Remote.parent, false)
    assert_equal(Legs.incoming.first.parent, Legs)
  end

  def test_send_bang
    assert_equal(123, Remote.echo(123))
    assert_equal(123, Remote.send!(:echo, 123))
    
    # check async
    abc = 0
    Remote.echo(123) { |r| abc = r.value }
    sleep(0.2)
    assert_equal(123, abc)
    
    # check it catches ancestor method calls
    assert_equal('overridden', Remote.methods)
  end

  def test_socket
    assert_equal(true, Remote.socket.is_a?(BasicSocket))
  end
  
  def test_marshaling
    object = Remote.marshal
    assert_equal(1, object.a)
    assert_equal(2, object.b)
    assert_equal(3, object.c)
  end
end

module TestLegs
  class TestResult < Test::Unit::TestCase
    def test_data
      result = nil
      Remote.echo(123) { |r| result = r }
      sleep(0.2)
      
      assert_equal(123, result.data['result'])
    end

    def test_result
      normal_result = Legs::Result.new({'id'=>1, 'result' => 'Hello World'})
      error_result  = Legs::Result.new({'id'=>2, 'error' => 'Uh oh Spagetti-o\'s'})

      assert_equal(normal_result.value, 'Hello World')
      assert_equal(normal_result.result, 'Hello World')
      assert_equal((error_result.value rescue :good), :good)
    end
  end
end

