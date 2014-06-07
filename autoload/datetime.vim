" Vim library providing datetime type
" Maintainer:	Barry Arthur <barry.arthur@gmail.com>
" Version:	0.1
" Description:	datetime type for VimL. Create dates from seconds, iso 8601
"		strings, or other datetime objects. Compare, diff and adjust
"		dates. Store dates in iso 8601 UTC (Zulu) format strings.
" Last Change:	2014-06-07
" License:	Vim License (see :help license)
" Location:	autoload/datetime.vim
" Website:	https://github.com/dahu/datetime
"
" See datetime.txt for help.  This can be accessed by doing:
"
" :helptags ~/.vim/doc
" :help datetime

" Vimscript Setup: {{{1
" Allow use of line continuation.
let s:save_cpo = &cpo
set cpo&vim

" load guard
if exists("g:loaded_lib_datetime")
      \ || v:version < 700
      \ || &compatible
  let &cpo = s:save_cpo
  " finish
endif
let g:loaded_lib_datetime = 1

" Vim Script Information Function: {{{1
function! datetime#info()
  let info = {}
  let info.name = 'datetime'
  let info.version = 1.0
  let info.description = 'datetime type for VimL'
  let info.dependencies = []
  return info
endfunction

" Helper functions taken from Tim Pope's vim-speeddating {{{1

" In Vim, -4 % 3 == -1.  Let's return 2 instead.
function! datetime#mod(a, b)
  if (a:a < 0 && a:b > 0 || a:a > 0 && a:b < 0) && a:a % a:b != 0
    return (a:a % a:b) + a:b
  else
    return a:a % a:b
  endif
endfunction

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

function! datetime#gregorian(jd)
  let l = a:jd + 68569
  let n = datetime#div(4 * l, 146097)
  let l = l - datetime#div(146097 * n + 3, 4)
  let i = (4000 * (l + 1)) / 1461001
  let l = l - (1461 * i) / 4 + 31
  let j = (80 * l) / 2447
  let d = l - (2447 * j) / 80
  let l = j / 11
  let m = j + 2 - (12 * l)
  let y = 100 * (n - 49) + i + l
  return {'year':y, 'month':m, 'day':d}
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
        \ - s:epoch_jd
  let real_ts = datetime.depoch * 86400 + datetime.hour * 3600 + datetime.minute * 60
        \ + datetime.second
  let datetime.stzoffset = (real_ts - ts)
  let datetime.mtzoffset = (real_ts - ts) / 60
  let datetime.htzoffset = datetime.mtzoffset / 60

  func datetime.to_seconds() dict
    return self.sepoch
  endfunc

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

function! datetime#days_to_ymd_from_epoch(days)
  let dt = datetime#localtime(datetime#days_to_seconds(a:days))
  return [dt.year - 1970, dt.month - 1, dt.day - 1]
endfunction

function! datetime#jd_to_ymd(jd)
  let dt = datetime#localtime(datetime#days_to_seconds(a:jd))
  return [dt.year, dt.month, dt.day]
endfunction

function! datetime#jd_to_gregorian(jd)
  return datetime#gregorian(a:jd)
endfunction


function! datetime#seconds_to_days(seconds)
  return datetime#div(a:seconds, 86400)
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

" Accepts a fully formed ISO 8601 datetime string in UTC:
" yyyy-mm-ddThh:MM:ssZ
"   %Y-%m-%dT%H:%M:%SZ (in strftime format)
function! datetime#utc_string_to_seconds(utc_s)
    if a:utc_s =~ '^\d\{4\}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
      let [y, m, d, h, M, s] = matchlist(a:utc_s,
            \ '^\(\d\{4\}\)-\(\d\d\)-\(\d\d\)T\(\d\d\):\(\d\d\):\(\d\d\)Z$')[1:6]
      let seconds  = s
      let seconds += datetime#minutes_to_seconds(M)
      let seconds += datetime#hours_to_seconds(h)
      let seconds += datetime#days_to_seconds(datetime#jd(y, m, d) - s:epoch_jd)
    else
      throw 'Unrecognised date format: ' . a:utc_s
    endif
    return seconds
endfunction

function! datetime#to_seconds(datetime)
  let dt = a:datetime
  let seconds = 0
  if type(dt) == type(0)
    let seconds = dt
  elseif type(dt) == type({})
    if has_key(dt, 'to_seconds')
      let seconds = dt.to_seconds()
    else
      throw 'Unknown object: lacks to_seconds() function.'
    endif
  elseif type(dt) == type('')
    if dt  == ''
      let seconds = datetime#localtime().to_seconds()
    else
      let seconds = datetime#utc_string_to_seconds(dt)
    endif
  else
    throw 'Unexpected type: ' . type(dt)
  endif
  return seconds
endfunction
" }}}1
" Additional datetime utility functions {{{1

" datetime#compare(datetime, datetime) - for sort()
function! datetime#compare(d1, d2)
  let s1 = datetime#to_seconds(a:d1)
  let s2 = datetime#to_seconds(a:d2)
  return (s1 == s2) ? 0 : (s1 > s2) ? 1 : -1
endfunction

" returns the difference between two dates in seconds
function! datetime#diff(d1, d2)
  let s1 = datetime#to_seconds(a:d1)
  let s2 = datetime#to_seconds(a:d2)
  return s1 - s2
endfunc
" }}}1
" DateTime Type {{{1

function! datetime#new(...)
  let obj = {}
  let obj.utcz_format = '%Y-%m-%dT%H:%M:%SZ'
  let dt = a:0 ? a:1 : ''

  func obj.initialize(...) dict
    let dt = a:0 ? a:1 : ''
    let self.datetime = datetime#localtime(datetime#to_seconds(dt))
    return self
  endfunc

  func obj.compare(other) dict
    return datetime#compare(self, a:other)
  endfunc

  func obj.eq(other) dict
    return self.compare(a:other) == 0
  endfunc

  func obj.leq(other) dict
    return self.compare(a:other) <= 0
  endfunc

  func obj.geq(other) dict
    return self.compare(a:other) >= 0
  endfunc

  func obj.before(other) dict
    return self.compare(a:other) == -1
  endfunc

  func obj.after(other) dict
    return self.compare(a:other) == 1
  endfunc

  func obj.diff(other) dict
    return datetime#diff(self, a:other)
  endfunc

  func obj.add(other) dict
    let self.datetime = datetime#localtime(self.datetime.to_seconds()
          \ + datetime#to_seconds(a:other))
    return self
  endfunc

  func obj.sub(other) dict
    let self.datetime = datetime#localtime(self.datetime.to_seconds()
          \ - datetime#to_seconds(a:other))
    return self
  endfunc

  func obj.adjust(amount) dict
    let amount = a:amount
    let adjusted = 0
    if type(amount) == type('')
      " space separated entries
      " e.g.   1y 2m -3d 4h +5M 6s
      " NOTE: 'm' and 'M' are case sensitive, but the others are not
      let seconds = 0
      let [y, m , d] = datetime#jd_to_ymd(self.datetime.depoch)
      for amt in split(amount, '\s\+')
        let [n, type] = matchlist(amt, '\c\([-+]\?\d\+\)\([ymdhs]\)')[1:2]
        if type == 'y'
          let y += n
        elseif type ==# 'm'
          let m += n
        elseif type == 'd'
          let d += n
        elseif type == 'h'
          let seconds += datetime#hours_to_seconds(n)
        elseif type ==# 'M'
          let seconds += datetime#minutes_to_seconds(n)
        elseif type == 's'
          let seconds += n
        else
          throw 'Unknown adjustment type: ' . string(type)
        endif
      endfor
      let seconds += datetime#days_to_seconds(datetime#jd(y, m, d) - s:epoch_jd)
      let self.datetime = datetime#localtime(seconds)
      let adjusted = 1
    else
      let seconds = datetime#to_seconds(amount)
    endif
    if ! adjusted
      let self.datetime = datetime#localtime(self.datetime.to_seconds() + seconds)
    endif
    return self
  endfunction

  func obj.to_gregorian() dict
    return datetime#jd_to_gregorian(s:epoch_jd + self.datetime.depoch)
  endfunc

  func obj.to_seconds() dict
    return self.datetime.to_seconds()
  endfunc

  func obj.to_string(...) dict
    let format = a:0 ? a:1 : self.utcz_format
    return strftime(format, self.datetime.to_seconds())
  endfunc

  func obj.to_utc_string(...) dict
    let format = a:0 ? a:1 : self.utcz_format
    return strftime(format, self.datetime.to_seconds() - self.datetime.stzoffset)
  endfunc

  return obj.initialize(dt)
endfunction

" }}}1
" Unit Tests (only run when loaded as   :source %) {{{1
if expand('%:p') == expand('<sfile>:p')
  let s:idx = 1

  function! AssertEq(a, b)
    let s = s:idx . ' ' . (a:a == a:b ? 'OK' : 'Fail')
    if s =~ 'Fail$'
      echohl Error
      echo s
      echohl None
    else
      echo s
    endif
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
  let d2 = datetime#new(d1.datetime.to_seconds() + 1)
  call AssertEq(-1, d1.compare(d2))
  call AssertEq( 1, d2.compare(d1))
  call AssertEq( 0, d1.compare(d1b))
  call AssertEq( 1, d1.eq(d1b))
  call AssertEq( 1, d1.leq(d2))
  call AssertEq( 1, d2.geq(d1))
  call AssertEq( 1, d2.after(d1))
  call AssertEq( 1, d1.before(d2))

  " specify time of new objects
  let t = localtime()
  let lt = datetime#localtime(t)
  let d1 = datetime#new(lt)
  let d2 = datetime#new()
  let d3 = datetime#new(d1)
  let d4 = datetime#new(d1.datetime)
  call AssertEq( 1, d1.eq(d2))
  call AssertEq( 1, d3.eq(d1))
  call AssertEq( 1, d4.eq(d1))
  call AssertEq( t, lt.to_seconds())
  call AssertEq( t, d1.to_seconds())
  call AssertEq(d1.to_seconds(), d2.to_seconds())

  let d5 = datetime#new('1970-01-01T00:00:00Z')
  let d6 = datetime#new('1960-01-01T00:00:00Z')
  let d7 = datetime#new('1980-01-01T00:00:00Z')
  call AssertEq('1970-01-01T00:00:00Z', d5.to_utc_string())
  call AssertEq('1960-01-01T00:00:00Z', d6.to_utc_string())
  call AssertEq('1980-01-01T00:00:00Z', d7.to_utc_string())
  call AssertEq([1970, 1, 1], datetime#jd_to_ymd(d5.datetime.depoch))
  call AssertEq({'year':1970, 'month':1, 'day':1 }, d5.to_gregorian())
  call AssertEq([0, 0, 0], datetime#days_to_ymd_from_epoch(d5.datetime.depoch))
  call AssertEq([1960, 1, 1], datetime#jd_to_ymd(d6.datetime.depoch))
  call AssertEq({'year':1960, 'month':1, 'day':1 }, d6.to_gregorian())
  call AssertEq([-10, 0, 0], datetime#days_to_ymd_from_epoch(d6.datetime.depoch))
  call AssertEq([1980, 1, 1], datetime#jd_to_ymd(d7.datetime.depoch))
  call AssertEq({'year':1980, 'month':1, 'day':1 }, d7.to_gregorian())
  call AssertEq([10, 0, 0], datetime#days_to_ymd_from_epoch(d7.datetime.depoch))
  " TODO: Is the day=1 below a TZ error?
  call AssertEq([10, 0, 1], datetime#days_to_ymd_from_epoch(
        \ datetime#seconds_to_days(d5.diff(d6))))
  call AssertEq([-10, 0, 0], datetime#days_to_ymd_from_epoch(
        \ datetime#seconds_to_days(d6.diff(d5))))

  " adjusting datetimes
  call d5.adjust('1y 2m 3d 4h 5M 6s')
  call AssertEq('1971-03-04T04:05:06Z', d5.to_utc_string())
  call d6.adjust('-1y -2m -3d -4h -5M -6s')
  " 1959-01-01:00:00:00
  " 1958-11-01:00:00:00
  " 1958-10-29:00:00:00
  " 1958-10-28:20:00:00
  " 1958-10-28:19:55:00
  " 1958-10-28:19:54:54
  call AssertEq('1958-10-28T19:54:54Z', d6.to_utc_string())
  call AssertEq({'year':1958, 'month':10, 'day':29 }, d6.to_gregorian())
  " discrepancy between 'day' values there due to timezone of author

  call AssertEq('1980-01-02T00:00:00Z', d7.add(datetime#days_to_seconds(1)).to_utc_string())
  call AssertEq('1980-01-01T00:00:00Z', d7.sub(datetime#days_to_seconds(1)).to_utc_string())

  let x = d6.to_utc_string()
  let y = datetime#new(x)
  call AssertEq(d6.adjust('1d').to_seconds(), y.adjust('1d').to_seconds())
endif

" }}}1
" Teardown:{{{1
"reset &cpo back to users setting
let &cpo = s:save_cpo

" Template From: https://github.com/dahu/Area-41/
" vim: set sw=2 sts=2 et fdm=marker:
