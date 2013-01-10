
# pull in external modules
gLong = require '../vendor/gLong.js'
exceptions = require './exceptions'

"use strict"

# things assigned to root will be available outside this module
root = exports ? self.util ?= {}

root.INT_MAX = Math.pow(2, 31) - 1
root.INT_MIN = -root.INT_MAX - 1 # -2^31

root.FLOAT_POS_INFINITY = Math.pow(2,128)
root.FLOAT_NEG_INFINITY = -1*root.FLOAT_POS_INFINITY

root.int_mod = (rs, a, b) ->
  exceptions.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b == 0
  a % b

root.int_div = (rs, a, b) ->
  exceptions.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b == 0
  # spec: "if the dividend is the negative integer of largest possible magnitude
  # for the int type, and the divisor is -1, then overflow occurs, and the
  # result is equal to the dividend."
  return a if a == root.INT_MIN and b == -1
  (a / b) | 0

root.long_mod = (rs, a, b) ->
  exceptions.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b.isZero()
  a.modulo(b)

root.long_div = (rs, a, b) ->
  exceptions.java_throw rs, 'java/lang/ArithmeticException', '/ by zero' if b.isZero()
  a.div(b)

root.float2int = (a) ->
  if a > root.INT_MAX then root.INT_MAX
  else if a < root.INT_MIN then root.INT_MIN
  else a|0

root.intbits2float = (uint32) ->
  if Int32Array?
    i_view = new Int32Array [uint32]
    f_view = new Float32Array i_view.buffer
    return f_view[0]

  # Fallback for older JS engines
  sign = (uint32 &       0x80000000)>>>31
  exponent = (uint32 &   0x7F800000)>>>23
  significand = uint32 & 0x007FFFFF
  if exponent is 0  # we must denormalize!
    value = Math.pow(-1,sign)*significand*Math.pow(2,-149)
  else
    value = Math.pow(-1,sign)*(1+significand*Math.pow(2,-23))*Math.pow(2,exponent-127)
  return value

# Checks if the given float is NaN
root.is_float_NaN = (a) ->
  # A float is NaN if it is greater than or less than the infinity
  # representation
  return a > root.FLOAT_POS_INFINITY || a < root.FLOAT_NEG_INFINITY

# Call this ONLY on the result of two non-NaN numbers.
root.wrap_float = (a) ->
  return root.FLOAT_POS_INFINITY if a > 3.40282346638528860e+38
  return 0 if 0 < a < 1.40129846432481707e-45
  return root.FLOAT_NEG_INFINITY if a < -3.40282346638528860e+38
  return 0 if 0 > a > -1.40129846432481707e-45
  a

root.cmp = (a,b) ->
  return 0  if a == b
  return -1 if a < b
  return 1  if a > b
  return null # this will occur if either a or b is NaN

# implements x<<n without the braindead javascript << operator
# (see http://stackoverflow.com/questions/337355/javascript-bitwise-shift-of-long-long-number)
root.lshift = (x,n) -> x*Math.pow(2,n)

root.read_uint = (bytes) ->
  n = bytes.length-1
  # sum up the byte values shifted left to the right alignment.
  sum = 0
  for i in [0..n] by 1
    sum += root.lshift(bytes[i],8*(n-i))
  sum

# Convert :count chars starting from :offset in a Java character array into a JS string
root.chars2js_str = (jvm_carr, offset, count) ->
  root.bytes2str(jvm_carr.array).substr(offset ? 0, count)

root.bytestr_to_array = (bytecode_string) ->
  (bytecode_string.charCodeAt(i) & 0xFF for i in [0...bytecode_string.length] by 1)

root.array_to_bytestr = (bytecode_array) -> String.fromCharCode(bytecode_array...)

root.parse_flags = (flag_byte) -> {
    public:       flag_byte & 0x1
    private:      flag_byte & 0x2
    protected:    flag_byte & 0x4
    static:       flag_byte & 0x8
    final:        flag_byte & 0x10
    synchronized: flag_byte & 0x20
    super:        flag_byte & 0x20
    volatile:     flag_byte & 0x40
    transient:    flag_byte & 0x80
    native:       flag_byte & 0x100
    interface:    flag_byte & 0x200
    abstract:     flag_byte & 0x400
    strict:       flag_byte & 0x800
  }

root.escape_whitespace = (str) ->
  str.replace /\s/g, (c) ->
    switch c
      when "\n" then "\\n"
      when "\r" then "\\r"
      when "\t" then "\\t"
      when "\v" then "\\v"
      when "\f" then "\\f"
      else c

# if :entry is a reference, display its referent in a comment
root.format_extra_info = (entry) ->
  type = entry.type
  info = entry.deref?()
  return "" unless info
  switch type
    when 'Method', 'InterfaceMethod'
      "\t//  #{info.class}.#{info.sig}"
    when 'Field'
      "\t//  #{info.class}.#{info.name}:#{info.type}"
    when 'NameAndType' then "//  #{info.name}:#{info.type}"
    else "\t//  " + root.escape_whitespace info if root.is_string info

class root.BytesArray
  constructor: (@raw_array, @start=0, @end=@raw_array.length) ->
    @_index = 0

  rewind: -> @_index = 0

  pos: -> @_index

  skip: (bytes_count) -> @_index += bytes_count

  has_bytes: -> @start + @_index < @end

  get_uint: (bytes_count) ->
    rv = root.read_uint @raw_array.slice(@start + @_index, @start + @_index + bytes_count)
    @_index += bytes_count
    return rv

  get_int: (bytes_count) ->
    bytes_to_set = 32 - bytes_count * 8
    @get_uint(bytes_count) << bytes_to_set >> bytes_to_set

  read: (bytes_count) ->
    rv = @raw_array[@start+@_index...@start+@_index+bytes_count]
    @_index += bytes_count
    rv

  peek: -> @raw_array[@start+@_index]

  size: -> @end - @start - @_index

  splice: (len) ->
    arr = new root.BytesArray @raw_array, @start+@_index, @start+@_index+len
    @_index += len
    arr

root.initial_value = (type_str) ->
  if type_str is 'J' then gLong.ZERO
  else if type_str[0] in ['[','L'] then null
  else 0

root.is_string = (obj) -> typeof obj == 'string' or obj instanceof String

# Walks up the prototype chain of :object looking for an entry in the :handlers
# dict that match its constructor's name.
root.lookup_handler = (handlers, object) ->
  obj = object
  while obj?
    # XXX: this will break on IE (due to constructor.name being undefined)
    handler = handlers[obj.constructor.name]
    return handler if handler
    obj = Object.getPrototypeOf obj
  return null

# Java classes are represented internally using slashes as delimiters.
# These helper functions convert between the two representations.
root.ext_classname = (str) -> str.replace /\//g, '.'
root.int_classname = (str) -> str.replace /\./g, '/'

# Parse Java's pseudo-UTF-8 strings. (spec 4.4.7)
root.bytes2str = (bytes) ->
  idx = 0
  char_array =
    while idx < bytes.length
      # cast to an unsigned byte
      x = bytes[idx++] & 0xff
      break if x == 0
      String.fromCharCode(
        if x <= 0x7f
          x
        else if x <= 0xdf
          y = bytes[idx++]
          ((x & 0x1f) << 6) + (y & 0x3f)
        else
          y = bytes[idx++]
          z = bytes[idx++]
          ((x & 0xf) << 12) + ((y & 0x3f) << 6) + (z & 0x3f)
      )
  char_array.join ''

root.last = (array) -> array[array.length-1]

class root.SafeMap

  constructor: ->
    @cache = Object.create null # has no defined properties aside from __proto__
    @proto_cache = undefined

  get: (key) ->
    return @cache[key] if @cache[key]? # don't use `isnt undefined` -- __proto__ is null!
    return @proto_cache if key.toString() is '__proto__' and @proto_cache isnt undefined
    undefined

  set: (key, value) ->
    # toString() converts key to a primitive, so strict comparison works
    unless key.toString() is '__proto__'
      @cache[key] = value
    else
      @proto_cache = value
