# Makes use of ZenTest. Install the 'ZenTest' gem, then run this ruby script in a terminal to see the results!
require 'test/unit' unless defined? $ZENTEST and $ZENTEST
require '../lib/legs'

# want to see errors, don't want to see excessively verbose logging normally
Thread.abort_on_exception = true
#Legs.log = true

# class to test the marshaling
class Marshal::TesterClass; attr_accessor :a, :b, :c; end

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
    obj = Marshal::TesterClass.new
    obj.a = 1; obj.b = 2; obj.c = 3
    return obj
  end
  
  def on_connect
    $server_instance = caller
  end
  
  def on_some_event
    $some_event_ran = true
  end
  
  # tests that we can call stuff back over the caller's socket
  def bidirectional; caller.notify!(:bidirectional_test_reciever); end
  def bidirectional_test_reciever; $bidirectional_worked = true; end
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
    assert_equal(true, Legs.outgoing.is_a?(Array))
    assert_equal(1, Legs.outgoing.length)
  end
  
  def test_class_open
    instance = nil
    Legs.open('localhost', 6425) do |i|
      instance = i
    end
    assert_equal(Legs, instance.class)
  end

  def test_class_started_eh
    assert_equal(true, Legs.started?)
  end

  def test_connected_eh
    assert_equal(true, Remote.connected?)
  end

  def test_close_bang
    ii = Legs.new('localhost', 6425)
    assert_equal(2, Legs.outgoing.length)
    ii.close!
    assert_equal(1, Legs.outgoing.length)
  end

  def test_meta
    assert_equal(true, Remote.meta.is_a?(Hash))
    Remote.meta[:yada] = 'Yada'
    assert_equal('Yada', Remote.meta[:yada])
  end

  def test_notify_bang
    $notified = false
    Remote.notify! :notified
    sleep(0.2)
    assert_equal(true, $notified)
  end

  def test_parent
    assert_equal(false, Remote.parent)
    assert_equal(Legs, Legs.incoming.first.parent)
  end

  def test_send_bang
    assert_equal(123, Remote.echo(123))
    assert_equal(123, Remote.send!(:echo, 123))
    
    # check async
    abc = 0
    Remote.echo(123) { |r| abc = r.value }
    sleep 0.2
    assert_equal(123, abc)
    
    # check it catches ancestor method calls
    assert_equal('overridden', Remote.methods)
  end
  
  def test_symbol_marshaling
    assert_equal(Symbol, Remote.echo(:test).class)
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
  
  def test_bidirectional
   $bidirectional_worked = false; Remote.bidirectional; sleep 0.2
   assert_equal(true, $bidirectional_worked)
  end
  
  # makes sure the block adding thingos work
  def test_adding_block
    @bound_var = bound_var = 'Ladedadedah'
    Legs.define_method(:defined_meth) { bound_var }
    assert_equal(bound_var, Remote.defined_meth)
    
    Legs.add_block(:unbound_meth) { @bound_var }
    assert_equal(bound_var, Remote.unbound_meth)
  end
  
  # this is to make sure we can run the start method a ton of times without bad side effects
  def test_start_again_and_again
    Legs.start
    Legs.start { def adding_another_method; true; end }
    assert_equal(true, Remote.adding_another_method)
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

