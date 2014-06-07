" Helper functions taken from Tim Pope's vim-speeddating {{{1
" In Vim, -4 / 3 == -1.  Let's return -2 instead.
function! datetime#div(a, b)
  if a:a < 0 && a:b > 0
    return (a:a - a:b + 1) / a:b
  elseif a:a > 0 && a:b < 0
    return (a:a - a:b - 1) / a:b
  else
    return a:a / a:b
  endif
endfunction

" Julian day (always Gregorian calendar)
function! datetime#jd(year, mon, day)
  let y = a:year + 4800 - (a:mon <= 2)
  let m = a:mon + (a:mon <= 2 ? 9 : -3)
  let jul = a:day + (153 * m + 2) / 5 + datetime#div(1461 * y, 4) - 32083
  return jul - datetime#div(y, 100) + datetime#div(y, 400) + 38
endfunction

let s:epoch_jd = datetime#jd(1970, 1, 1)

function! datetime#localtime(...)
  let ts  = a:0 ? a:1 : has('unix') ? reltimestr(reltime()) : localtime() . '.0'
  let us  = matchstr(ts, '\.\zs.\{0,6\}')
  let us .= repeat(0, 6 - strlen(us))
  let us  = matchstr(us, '[1-9].*')
  " sepoch    = seconds since epoch (Jan 1, 1970)
  " depoch    = days since epoch
  " stzoffset = timezone offset from UTC in seconds
  " mtzoffset = timezone offset from UTC in minutes
  " htzoffset = timezone offset from UTC in hours
  " the + in +strftime() converts strings into numbers
  let datetime = {
        \  'year'   : +strftime('%Y', ts)
        \, 'month'  : +strftime('%m', ts)
        \, 'day'    : +strftime('%d', ts)
        \, 'hour'   : +strftime('%H', ts)
        \, 'minute' : +strftime('%M', ts)
        \, 'second' : +strftime('%S', ts)
        \, 'sepoch' : +strftime('%s', ts)
        \, 'smicro' : us / 1000}
  let datetime.depoch = datetime#jd(datetime.year, datetime.month, datetime.day)
        \ - datetime#jd(1970, 1, 1)
  let real_ts = datetime.depoch * 86400 + datetime.hour * 3600 + datetime.minute * 60
        \ + datetime.second
  let datetime.stzoffset = (real_ts - ts)
  let datetime.mtzoffset = (real_ts - ts) / 60
  let datetime.htzoffset = datetime.mtzoffset / 60
  return datetime
endfunction
" }}}1

" datetime conversion functions {{{1
function! datetime#minutes_to_seconds(minutes)
  return a:minutes * 60
endfunction

function! datetime#hours_to_seconds(hours)
  return datetime#minutes_to_seconds(a:hours * 60)
endfunction

function! datetime#days_to_seconds(days)
  return datetime#hours_to_seconds(a:days * 24)
endfunction

function! datetime#weeks_to_seconds(weeks)
  return datetime#days_to_seconds(a:weeks * 7)
endfunction

function! datetime#months_to_seconds(months)
  return datetime#days_to_seconds(a:months * 30)
endfunction

function! datetime#years_to_seconds(years)
  return datetime#days_to_seconds(a:years * 365)
endfunction

" }}}1

" additional datetime utility functions {{{1

" datetime#compare(datetime, datetime) - for sort()
function! datetime#compare(d1, d2)
  return (a:d1.datetime.sepoch == a:d2.datetime.sepoch) ? 0
        \ : (a:d1.datetime.sepoch > a:d2.datetime.sepoch) ? 1 : -1
endfunction

" datetime type {{{1
function! datetime#new(...)
  let obj = {}
  let init_time = a:0 ? a:1 : ''

  func obj.initialize(...)
    let init_time = a:0 ? a:1 : ''
    let self.datetime = {}
    if type(init_time) == type(0)
      let seconds = init_time
    elseif type(init_time) == type({})
      if has_key(init_time, 'datetime')
        let seconds = init_time.datetime.sepoch
      elseif has_key(init_time, 'sepoch')
        let seconds = init_time.sepoch
      else
        throw 'Unknown object: lacks datetime or sepoch fields.'
      endif
    elseif type(init_time) == type('')
      if init_time == ''
        let self.datetime = datetime#localtime()
      elseif init_time =~ '^\d\{4\}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
        let [y, m, d, h, M, s] = matchlist(init_time,
              \ '^\(\d\{4\}\)-\(\d\d\)-\(\d\d\)T\(\d\d\):\(\d\d\):\(\d\d\)Z$')[1:6]
        let seconds  = s
        let seconds += datetime#minutes_to_seconds(M)
        let seconds += datetime#hours_to_seconds(h)
        let seconds += datetime#days_to_seconds(datetime#jd(y, m, d) - s:epoch_jd)
      else
        throw 'Unknown date format: ' . type
      endif
    else
      throw 'Unexpected init_time type: ' . string(type)
    endif
    if empty(self.datetime)
      let self.datetime = datetime#localtime(seconds)
    endif
    return self
  endfunc

  func obj.compare(other)
    return datetime#compare(self, a:other)
  endfunc

  func obj.eq(other)
    return self.compare(a:other) == 0
  endfunc

  func obj.leq(other)
    return self.compare(a:other) <= 0
  endfunc

  func obj.geq(other)
    return self.compare(a:other) >= 0
  endfunc

  func obj.before(other)
    return self.compare(a:other) == -1
  endfunc

  func obj.after(other)
    return self.compare(a:other) == 1
  endfunc

  func obj.diff(other)
    return self.datetime.sepoch - a:other.datetime.sepoch
  endfunc

  func obj.add(other)
    let self.datetime = datetime#localtime(self.datetime.sepoch
          \ + a:other.datetime.sepoch)
    return self
  endfunc

  func obj.sub(other)
    let self.datetime = datetime#localtime(self.datetime.sepoch
          \ - a:other.datetime.sepoch)
    return self
  endfunc

  func obj.adjust(amount)
    let amount = a:amount
    if type(amount) == type(0)
      let seconds = amount
    elseif type(amount) == type({})
      if has_key(amount, 'datetime')
        let seconds = amount.datetime.sepoch
      elseif has_key(amount, 'sepoch')
        let seconds = amount.sepoch
      else
        throw 'Unknown object: lacks datetime or sepoch fields.'
      endif
    elseif type(amount) == type('')
      " space separated entries
      " e.g.   1y 2m -3d 4h +5M 6s
      let seconds = 0
      for amt in split(amount, '\s\+')
        let [n, type] = matchlist(amt, '\c\([-+]\?\d\+\)\([ymbdhMs]\)')[1:2]
        if type == 'y'
          let seconds += datetime#years_to_seconds(n)
        elseif (type == 'm' || type == 'b')  " handle tpope's speeddating convention
          let seconds += datetime#months_to_seconds(n)
        elseif type == 'd'
          let seconds += datetime#days_to_seconds(n)
        elseif type == 'h'
          let seconds += datetime#hours_to_seconds(n)
        elseif type == 'M'
          let seconds += datetime#minutes_to_seconds(n)
        elseif type == 's'
          let seconds += n
        else
          throw 'Unknown adjustment type: ' . string(type)
        endif
      endfor
    else
      throw 'Unexpected amount type: ' . string(type)
    endif
    let self.datetime = datetime#localtime(self.datetime.sepoch + seconds)
    return self
  endfunction

  func obj.to_seconds() dict
    return self.sepoch
  endfunc

  func obj.to_s(...) dict
    let format = a:0 ? a:1 : '%Y-%m-%dT%H:%M:%SZ'
    return strftime(format, self.datetime.sepoch)
  endfunc

  func obj.to_utc_s(...) dict
    let format = a:0 ? a:1 : '%Y-%m-%dT%H:%M:%SZ'
    return strftime(format, self.datetime.sepoch - self.datetime.stzoffset)
  endfunc

  return obj.initialize(init_time)
endfunction




if expand('%:p') == expand('<sfile>:p')
  let s:idx = 1
  function! AssertEq(a, b)
    echo s:idx . ' ' . (a:a == a:b ? 'OK' : 'Fail')
    let s:idx += 1
  endfunction
  call AssertEq((7 *  60)               , datetime#minutes_to_seconds(7))
  call AssertEq((7 *  60 * 60)          , datetime#hours_to_seconds(7))
  call AssertEq((7 *  24 * 60 * 60)     , datetime#days_to_seconds(7))
  call AssertEq((7 *   7 * 24 * 60 * 60), datetime#weeks_to_seconds(7))
  call AssertEq((7 *  30 * 24 * 60 * 60), datetime#months_to_seconds(7))
  call AssertEq((7 * 365 * 24 * 60 * 60), datetime#years_to_seconds(7))
  let d1 = datetime#new()
  let d1b = datetime#new()
  let d2 = datetime#new(d1.datetime.sepoch + 1)
  call AssertEq(-1, d1.compare(d2))
  call AssertEq( 1, d2.compare(d1))
  call AssertEq( 0, d1.compare(d1b))
  call AssertEq( 1, d1.eq(d1b))
  call AssertEq( 1, d1.leq(d2))
  call AssertEq( 1, d2.geq(d1))
  call AssertEq( 1, d2.after(d1))
  call AssertEq( 1, d1.before(d2))

  " specify time of new objects
  let d1 = datetime#new(localtime())
  let d2 = datetime#new()
  let d3 = datetime#new(d1)
  let d4 = datetime#new(d1.datetime)
  call AssertEq( 1, d1.eq(d2))
  call AssertEq( 1, d3.eq(d1))
  call AssertEq( 1, d4.eq(d1))
  let d5 = datetime#new('1970-01-01T00:00:00Z')
  let d6 = datetime#new('1960-01-01T00:00:00Z')
  let d7 = datetime#new('1980-01-01T00:00:00Z')
  call AssertEq('1970-01-01T00:00:00Z', d5.to_utc_s())
  call AssertEq('1960-01-01T00:00:00Z', d6.to_utc_s())
  call AssertEq('1980-01-01T00:00:00Z', d7.to_utc_s())
endif

" vim: fdm=marker
