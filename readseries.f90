subroutine readseries(infile,data,npermax,yrbeg,yrend,nperyear, &
    var,units,lstandardunits,lwrite)

!       file (in) filename to read.
!       this routines accepts 3 formats:
!       - a netCDF file with one time series
!       - an ascii file with lines with
!           'yyyy val_jan val_feb ... val_dec [val_year]'
!       - an ascii file with lines with year.fractionofyear value
!       - an ascii file with lines with year month value
!       - an ascii file with lines with year month day value
!       Comment line start with '#'
!       data (out) the data is returned in data, which is filled with
!       undef's where no data exists.
!       nperyear,yrbeg,yrend (out) dimensions of data
!       units,var (out) properties of file

!       I try to convert the units to my standard ones:
!       temp [C], prcp [mm/period], slp [hPa], ...

    implicit none
    include 'netcdf.inc'
    integer :: npermax,nperyear,yrbeg,yrend
    real :: data(npermax,yrbeg:yrend)
    character infile*(*),units*(*),var*(*)
    logical :: lstandardunits,lwrite
    integer :: i,j,k,m,year,month,day,unit,status,ncid,dpm(12), &
    dpm0(12),imonth,year1,reallynperyear,iarray1(13), &
    iarray2(13),iret1,iret2
    logical :: lagain,lexist
    real*8 :: x,y,x1,y1,val12(366)
    character file*1023,ncfile*1023,line*10000
    integer :: getnumwords,monthinline
    save dpm,dpm0
    data dpm0 /31,29,31,30,31,30,31,31,30,31,30,31/
    do i=1,12
        dpm(i) = dpm0(i)
    enddo

    if ( lwrite ) then
        print *,'readseries: opening file ',trim(infile)
        print *,'npermax,yrbeg,yrend = ',npermax,yrbeg,yrend
    endif
    call makeabsent(data,npermax,yrbeg,yrend)

!       also handle netCDF time series

    file = infile
    if ( file == '-' ) then
        unit = 5
    else
    ! check whether there is a netcdf file with the same name
    ! as that is read orders of magnitude faster
        i = index(file,'.dat')
        if ( i /= 0 ) then
            ncfile = file(:i-1)//'.nc'
            inquire(file=trim(ncfile),exist=lexist)
            if ( lexist ) then
            ! check that it is not older than the ascii file
                call mystat(trim(infile),iarray1,iret1)
                call mystat(trim(ncfile),iarray2,iret2)
                if ( iret1 == 0 .and. iret2 == 0 ) then
                    if ( iarray2(10) >= iarray1(10) ) then
                        file = ncfile
                        if ( lwrite ) then
                            print *,'readseries: using file ', &
                            trim(file)
                        end if
                    else
                        if ( lwrite ) print *,'readseries: remove'// &
                        'the out-of-date netcdf file ', &
                        trim(ncfile)
                        open(1,file=trim(ncfile))
                        close(1,status='delete',err=101)
                    101 continue
                    end if
                end if
            end if
        end if
                    
        status = nf_open(trim(file),nf_nowrite,ncid)
        if ( status /= nf_noerr ) then
            call rsunit(unit)
            if ( lwrite ) print *,'readseries: opening ',trim(file), &
            ' as ascii file on unit ',unit
            open(unit,file=trim(file),status='old',err=902)
        else
        !               it is a netCDF file
            if ( lwrite ) print *,'calling readncseries ',trim(file)
            call readncseries(file,data,npermax,nperyear,yrbeg,yrend &
            ,ncid,var,units,lwrite)
            if ( lstandardunits ) then
                call makestandardseries(data,npermax,yrbeg,yrend, &
                nperyear,var,units,lwrite)
            endif
            return
        endif
    endif
!       it is an ascii file.
    call readseriesheader(var,units,line,unit,lwrite)
    if ( line == ' ' ) then
        nperyear = 0        ! is undefined when there is no data
        if ( unit /= 5 ) close(unit)
        return
    endif
!       first look for explicit months
    imonth = monthinline(line)
    nperyear = getnumwords(line) - 1
    if ( nperyear == 2 ) then
    !           it is either half-yearly data: yr valOct-March valApr-Sep
    !           or monthly data: yr mo val
        read(line,*) year
        read(unit,*,end=801) year1
        if ( year == year1 ) then
            if ( lwrite ) print *,'monthly data'
            reallynperyear = 12
        else
            if ( lwrite ) print *,'seasonal data'
            reallynperyear = 2
        endif
        backspace(unit)
    801 continue
    endif
    if ( nperyear == 4 ) then
    !           it is either seasonal data: yr valDJF valMAM valJJA valSON
    !           or hourly data: yr mo dy hr val
        read(line,*) year
        read(unit,*,end=802) year1
        if ( year == year1 ) then
            if ( lwrite ) print *,'monthly data'
            nperyear = 12
        else
            if ( lwrite ) print *,'half-yearly data'
        endif
        backspace(unit)
    802 continue
    endif
!       often there is a yearly mean/sum at the end
    if ( nperyear == 13 ) nperyear = 12
    if ( nperyear > npermax ) then
        write(0,*) 'readseries: error: increase npermax ',npermax &
        ,nperyear
        write(*,*) 'readseries: error: increase npermax ',npermax &
        ,nperyear
        call exit(-1)
    endif
    if ( imonth > 0 ) then
        call readdymoyrval(data,npermax,yrbeg,yrend,nperyear,line &
        ,unit,lwrite)
    elseif ( nperyear == 1 ) then
        call readyrfracval(data,npermax,yrbeg,yrend,nperyear &
        ,line,unit,lwrite)
    elseif ( nperyear == 2 ) then
        if ( reallynperyear == 2 ) then
            call readyrval(data,npermax,yrbeg,yrend,nperyear,line, &
            unit,lwrite)
        else
            call readyrmoval(data,npermax,yrbeg,yrend,nperyear,line, &
            unit,lwrite)
        end if
    elseif ( nperyear == 3 ) then
        call readyrmodyval(data,npermax,yrbeg,yrend,nperyear,line &
        ,unit,lwrite)
    elseif ( nperyear == 366*24 ) then
        call readyrmodyhrval(data,npermax,yrbeg,yrend,nperyear,line &
        ,unit,lwrite)
    else
        call readyrval(data,npermax,yrbeg,yrend,nperyear,line,unit &
        ,lwrite)
    endif
    if ( unit /= 5 ) then
        if ( lwrite ) print *,'closing unit ',unit
        close(unit)
    end if
    if ( lstandardunits ) then
        call makestandardseries(data,npermax,yrbeg,yrend,nperyear &
        ,var,units,lwrite)
    endif
    return
    902 print *,'readseries: error opening ',trim(file)
    call exit(-1)
end subroutine readseries

subroutine readseriesheader(var,units,line,unit,lwrite)
!       read header, try to find the variable name and the units
!       it leaves the last (non-header) line read in line
    implicit none
    integer :: unit
    logical :: lwrite
    character var*(*),units*(*),line*(*)
    integer :: i,j,k,iline
    logical :: onlynumbers
    units = ' '
    var = ' '
    iline = 0
100 continue
    read(unit,'(a)',err=903,end=900) line
    if ( lwrite ) print *,'readseriesheader: processing line ' &
    ,trim(line)
!       the Mac sometimes gets confused and puts something else before
!       the '#'
    if ( line(1:1) == '#' .or. line(2:2) == '#' .or. &
    line == ' ' ) then
    !           do not count lines, but look for '#'
        if ( lwrite ) print *,'found new-style #-comments'
        iline = -1
    else if ( iline == -1 ) then
        if ( lwrite ) print *,'end of #-comments - return'
        return
    else if ( onlynumbers(line) ) then
        if ( lwrite ) print *,'line with only numbers - return'
        return
    else
        iline = iline + 1
    endif
    j = index(line,'[')
    if ( j > 0 ) then
        k = index(line,']')
        if ( k > j ) then
            units = line(j+1:k-1)
            call checkstring(units)
            j = 1 + index(line,';', .true. )
        ! ugly hack
            if ( j > 3 ) then
                if ( index(line(max(1,j-8):j-1),'&') /= 0 ) then
                    j = 1   ! not a break but an esacped HTML character code...
                end if
            end if
        110 continue
            if ( line(j:j) == ' ' ) then
                j = j + 1
                goto 110
            endif
            if ( line(j:j) == '#' ) then
                j = j + 2
            endif
            k = j + index(line(j:),' ') - 2
            var = line(j:k)
            if ( var == 'GDCN' ) then
            !                   hard-coded...
                j = 13
                k = j + index(line(j:),' ') - 2
                var = line(j:k)
                call tolower(var)
            endif
            call checkstring(var)
        endif
        if ( lwrite ) then
            print *,'found var  =',trim(var)
            print *,'found units=',trim(units)
        endif
    endif
    if ( iline < 5 ) goto 100
    read(unit,'(a)') line
    if ( lwrite ) print *,'First line with data ',trim(line)
    return
    900 line = ' '
    return
    903 print *,'readseriesheader: error reading header'
    print *,line
    call exit(-1)
end subroutine readseriesheader

logical function onlynumbers(line)
    implicit none
    character*(*) line
    integer :: i
    if ( line == ' ' ) then
        onlynumbers = .false. 
        return
    endif
    onlynumbers = .true. 
    do i=1,4
        if ( lge(line(i:i),'0') .and. lle(line(i:i),'9') .or. &
        line(i:i) == ' ' .or. line(i:i) == '\t' .or. &
        line(i:i) == '.' .or. line(i:i) == '-' .or. &
        line(i:i) == '\n' .or. line(i:i) == '\r' ) then
            cycle
        else
            onlynumbers = .false. 
            return
        endif
    end do
    do i=5,len(line)
        if ( lge(line(i:i),'0') .and. lle(line(i:i),'9') .or. &
        line(i:i) == ' ' .or. line(i:i) == '.' .or. &
        line(i:i) == '-' .or. line(i:i) == '+' .or. &
        line(i:i) == 'e' .or. line(i:i) == 'E' .or. &
        line(i:i) == 'd' .or. line(i:i) == 'D' .or. &
        line(i:i) == '\t' .or. &
        line(i:i) == '\n' .or. line(i:i) == '\r' ) then
            cycle
        else
            onlynumbers = .false. 
            return
        endif
    end do
    end function onlynumbers

    integer function monthinline(line)
    implicit none
    character line*(*)
    integer :: imonth
    call tolower(line)
    imonth = index(line,'jan')
    if ( imonth == 0 ) imonth = index(line,'feb')
    if ( imonth == 0 ) imonth = index(line,'mar')
    if ( imonth == 0 ) imonth = index(line,'apr')
    if ( imonth == 0 ) imonth = index(line,'may')
    if ( imonth == 0 ) imonth = index(line,'jun')
    if ( imonth == 0 ) imonth = index(line,'jul')
    if ( imonth == 0 ) imonth = index(line,'aug')
    if ( imonth == 0 ) imonth = index(line,'sep')
    if ( imonth == 0 ) imonth = index(line,'oct')
    if ( imonth == 0 ) imonth = index(line,'nov')
    if ( imonth == 0 ) imonth = index(line,'dec')
    monthinline = imonth
end function monthinline

subroutine readdymoyrval(data,npermax,yrbeg,yrend,nperyear,line &
    ,unit,lwrite)

!       format is NN-MON-YYYY, possibly with the dashes.
!       Assume daily data in a Gregorian calendar
!       TODO: other calendars, other nperyears.

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: imonth,j,m,day,month,year,dpm(12),dpm0(12)
    real*8 :: val
    integer :: monthinline
    save dpm,dpm0
    data dpm0 /31,29,31,30,31,30,31,31,30,31,30,31/

    if ( lwrite ) print *,'readdymoyrval: reading data as '// &
    'dd-mon-yyyy or ddmonyyyy'
    do month=1,12
        dpm(month) = dpm0(month)
    enddo
    nperyear = 366
 10 continue
    imonth = monthinline(line)
    if ( imonth <= 0 ) then
        write(0,'(a,i3,a)') &
        'readseries: cannot recognize month in ',imonth &
        ,line(imonth:imonth+2)
        write(0,'(a)') trim(line)
        goto 20
    endif
    month = (index &
    ('jan feb mar apr may jun jul aug sep oct nov dec' &
    ,line(imonth:imonth+2)) + 3)/4
    j = imonth-1
    if ( line(j:j) == '-' ) j = j-1
    if ( j-1 <= 0 ) goto 11
    read(line(j-1:j),*,end=1800,err=11) day
    if ( day < 1 .or. day > dpm(month) ) goto 11
    goto 12
 11 continue
    write(0,'(a,i8,a,i3,a)') 'readseries: strange day ',day &
    ,' in ',j,line(j-1:j)
    write(0,'(a)') trim(line)
    goto 20
 12 continue
    j = imonth+3
    if ( line(j:j) == '-' ) j = j + 1
    read(line(j:),*,err=13) year
    goto 14
 13 continue
    write(0,'(a,i8,a)') 'readseries: error reading year in'
    write(0,'(a)') trim(line)
    goto 20
 14 continue
    do m=1,month-1
        day = day + dpm(m)
    enddo
    read(line(imonth+8:),*) val
    call checkvalid(year,day,val)
    if ( val < 1e33 ) data(day,year) = val
!**     print *,day,year,data(day,year)
 20 continue
 30 continue
    read(unit,'(a)',err=904,end=1800) line
    if ( line == ' ' .or. index(line(1:2),'#') /= 0 ) goto 30
    call tolower(line)
    goto 10
1800 continue
    return
904 print *,'readdymoyrval: error reading data of line'
    print '(a)',trim(line)
    print '(a,2i3,g14.6)','last data read ',year,day,val
    call exit(-1)
end subroutine readdymoyrval

subroutine readyrval(data,npermax,yrbeg,yrend,nperyear,line,unit &
    ,lwrite)

!       format is year val(1) val(2) ...val(nperyear) (nperyear >= 4)

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: year,j
    real*8,allocatable :: val12(:)
    logical :: lfirst
    save lfirst
    data lfirst / .true. /

    if ( lwrite ) then
        print *,'readyrval: reading data as '// &
        'yyyy val1 val2 ... valN (N>3)'
        print *,'readyrval: npermax,yrbeg,yrend,nperyear = ',npermax &
        ,yrbeg,yrend,nperyear
    endif
    allocate(val12(npermax))
    read(line,*,err=904,end=300) year,(val12(j),j=1,nperyear)
100 continue
    if ( .false. .and. lwrite ) print *,'read year,val12 = ',year &
        ,(val12(j),j=1,nperyear)
    if ( year < yrbeg .or. year > yrend ) then
        if ( lfirst ) then
            lfirst = .false. 
            write(0,'(a,3i5)') '# disregarding year ',year,yrbeg,yrend
        endif
    else
        do j=1,nperyear
            call checkvalid(year,j,val12(j))
            if ( val12(j) < 1e33 ) data(j,year) = val12(j)
        enddo
    endif
200 continue
    read(unit,'(a)',err=300,end=300) line
    if ( line == ' ' .or. line(1:1) == '#' .or. line(2:2) == '#') then
        goto 200
    end if
    read(line,*,err=300,end=300) year,(val12(j),j=1,nperyear)
    goto 100
300 continue
    deallocate(val12)
    return
904 print *,'readyrval: error reading data of line'
    print '(a)',trim(line)
    print '(a,i4,1000g14.6)','last data read ',year,(val12(j),j=1 &
    ,nperyear)
    call exit(-1)
end subroutine readyrval

subroutine readyrfracval(data,npermax,yrbeg,yrend,nperyear,line &
    ,unit,lwrite)

!       format is year.frac value or yyyy[mm[dd[hh]]] value
!       Figure out nperyear from the data...

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: i,j,k,n,year,month,day,hour,year1,month1,day1,hour1,ymdh &
    ,dpm(12),nperyear1,jul,jul1
    integer,external :: julday,leap,getj
    save dpm
    real*8 :: x,y,x1,y1
    logical :: lfrac,lfirst
    logical :: onlynumbers
    save lfirst
    data dpm /31,29,31,30,31,30,31,31,30,31,30,31/
    data lfirst / .true. /

    i = scan(line,'123456789')
    if ( i == 0 ) then
        write(0,*) &
        'readyrfracval: error: cannot find 1 or 2 in line ' &
        ,trim(line)
        call exit(-1)
    end if
    j = scan(line(i:),' ')
    if ( j == 0 ) j = 9999
    k = scan(line(i:),achar(9))
    if ( k == 0 ) k = 9999
    j = min(j,k)
    if ( j == 9999 ) then
        write(0,*) 'readyrfracval: error: cannot find space or '// &
        'tab in ',trim(line(i:))
        call exit(-1)
    end if
    if ( lwrite ) print *,'looking for decimal point in ', &
    line(i:i+j-2)
    if ( index(line(i:i+j-2),'.') /= 0 ) then
        lfrac = .true. 
        if ( lwrite ) print *,'readyrfracval: reading data as '// &
        'yyyy.frac val'
    else
        lfrac = .false. 
        if ( lwrite ) print *,'readyrfracval: reading data as '// &
        'yyyy[mm[dd[hh]]] val'
    endif
    nperyear = 0
401 continue
    call tolower(line)
    if ( lfrac ) then
        read(line,*,err=904,end=500) x,y
        year = int(x+1e-4)
    else
        read(line,*,err=904,end=500) ymdh,y
        call yyyymmddhh(ymdh,year,month,day,hour)
        if ( lwrite ) print *,'read and interpreted ',year,month,day &
        ,hour,y
    endif
    call checkvalid(year,1,y)
    if ( y > 1e33 ) then
        if ( lwrite ) print *,'invalid data, try again'
   4015 continue
        read(unit,'(a)',err=904,end=1800) line
        if ( .not. onlynumbers(line) ) then
            if ( lwrite ) print *,'found line with non-numbers ' &
            ,trim(line)
            goto 4015
        endif
        if ( lwrite ) print *,'really try again'
        goto 401
    endif
    i = 0
402 continue
    i = i + 1
405 continue
    read(unit,'(a)',err=904,end=500) line
    if ( lwrite ) print *,'read line ',trim(line)
    if ( .not. onlynumbers(line) ) then
        if ( lwrite ) print *,'Found non-numbers in ',trim(line)
        goto 405
    end if
    if ( lfrac ) then
        read(line,*,err=904,end=500) x1,y1
        year1 = int(x+1e-4)
    else
        read(line,*,err=904,end=500) ymdh,y1
        call yyyymmddhh(ymdh,year1,month1,day1,hour1)
        if ( lwrite ) print *,'read and interpreted ',year1,month1 &
        ,day1,hour1,y1
        if ( day > dpm(month) .or. &
        day > 28 .and. month == 2 .and. leap(year) == 1 ) then
            write(0,'(a,2i3,i5)') &
            '# readseries: disregarded invalid date ',day,month &
            ,year
            goto 402
        end if
    endif
    call checkvalid(year1,2,y1)
    if ( y1 > 1e33 ) then
        if ( lwrite ) print *,'invalid data, try again'
        goto 402
    endif
    if ( lfrac ) then
        nperyear = max(nperyear,nint(i/(x1-x)))
    else
        jul = julday(month,day,year)
        jul1 = julday(month1,day1,year1)
        if ( jul == jul1 .and. hour == hour1 ) then
            write(0,*) 'readyrfracval: duplicate date 1 ',hour,day &
            ,month,year,hour1,day1,month1,year1
            goto 402
        end if
        nperyear = max(nperyear, &
        nint((24*366.)/(24*(jul1-jul) + (hour1-hour))))
    end if
!       round-off errors...
    call adjustnperyear(nperyear,lwrite)
    if ( lwrite ) then
        if ( lfrac ) then
            write(*,*) 'readyrfracval: found nperyear = ', &
            nperyear,i,x1,x,i/(x1-x)
        else
            write(*,*) 'readyrfracval: found nperyear = ', &
            nperyear
            write(*,*) year1,year
            write(*,*) month1,month
            write(*,*) day1,day
            write(*,*) hour1,hour
        endif
    endif
    if ( nperyear > npermax ) then
        write(0,*) 'readseries: error: increase npermax ',npermax &
        ,nperyear
        write(*,*) 'readseries: error: increase npermax ',npermax &
        ,nperyear
        call exit(-1)
    endif
    if ( lfrac ) then
        j = nint(nperyear*(x-year)+0.75001)
        if ( nperyear == 366 .and. leap(year) == 1 .and. j >= 60 ) &
        then
            j = 1 + nint(365*(x-year)+0.75001)
        end if
    else
        j = getj(month,day,hour,nperyear)
    endif
    call checkvalid(year,j,y)
    if ( year < yrbeg .or. year > yrend ) then
        if ( lfirst ) then
            lfirst = .false. 
            write(0,'(a,i5)') '# disregarding year ',year
        endif
    elseif ( y < 1e33 ) then
        if ( lwrite ) then
            print *,'data(',year,j,') = ',y
        endif
        data(j,year) = y
    endif
    450 continue
    if ( lfrac ) then
        year = int(x1+1e-4)
        j = nint(nperyear*(x1-year)+0.75001)
        if ( nperyear == 366 .and. leap(year) == 1 .and. j >= 60 ) &
        then
            j = 1 + nint(365*(x1-year)+0.75001)
        end if
    else
        j = getj(month1,day1,hour1,nperyear)
        year = year1
    endif
    call checkvalid(year,j,y1)
    if ( year < yrbeg .or. year > yrend ) then
        if ( lfirst ) then
            lfirst = .false. 
            write(0,'(a,i5)') '# disregarding year ',year
        endif
    elseif ( y1 < 1e33 ) then
        if ( lwrite ) then
            print *,'data(',year,j,') = ',y1
        endif
        data(j,year) = y1
    endif
    x = x1
    y = y1
    year = year1
    month = month1
    day = day1
    hour = hour1
460 continue
    read(unit,'(a)',err=904,end=500) line
    if ( .not. onlynumbers(line) ) goto 460
    if ( lfrac ) then
        read(line,*,err=904,end=500) x1,y1
        nperyear1 = nint(1/(x1-x))
        call adjustnperyear(nperyear1,lwrite)
    else
        read(line,*,err=904,end=500) ymdh,y1
        call yyyymmddhh(ymdh,year1,month1,day1,hour1)
        if ( day1 > dpm(month1) .or. &
        day1 > 28 .and. month1 == 2 .and. leap(year1) == 1 ) &
        then
            write(0,'(a,2i3,i5)') &
            '# readseries: disregarded invalid date ',day1 &
            ,month1,year1
            goto 460
        end if
        jul = julday(month,day,year)
        jul1 = julday(month1,day1,year1)
        if ( jul == jul1 .and. hour == hour1 ) then
            write(0,*) 'readyrfracval: duplicate date 2 ',hour,day &
            ,month,year,hour1,day1,month1,year1
            goto 460
        end if
        nperyear1 = nint((24*366.)/(24*(jul1-jul) + (hour1-hour)))
        if ( lwrite .and. nperyear1 /= nperyear ) then
            print *,'nperyear1 = ',nperyear1
            print *,'date  = ',year,month,day,hour
            print *,'date1 = ',year1,month1,day1,hour1
        end if
        call adjustnperyear(nperyear1,lwrite)
    endif
    if ( nperyear1 > nperyear ) then
        if ( lwrite ) print *,'adjusting nperyear from ',nperyear &
        ,' to ',nperyear1
        nperyear = nperyear1
    !           and start all over again
        data = 3e33
        rewind(unit)
    480 continue
        read(unit,'(a)') line
        if ( .not. onlynumbers(line) ) goto 480
        if ( lwrite ) print *,'restarting with line = ',trim(line)
        goto 401
    endif
    goto 450
    500 continue
    return
    1800 continue
    nperyear = 1
    if ( y < 1e33 ) data(1,year) = y
    return
    904 print *,'readyrfracval: error reading data of line'
    print '(a)',trim(line)
    if ( lfrac ) then
        print '(a,4g14.6)','last data read ',x1,y1,x,y
    else
        print '(a,4i4,g14.6)','last data read ',year1,month1,day1 &
        ,hour1,y1
    endif
    call exit(-1)
end subroutine readyrfracval

subroutine readyrmoval(data,npermax,yrbeg,yrend,nperyear,line &
    ,unit,lwrite)

!       format is year mon value
!       !!!Figure out nperyear from the data...
!       nperyear is set to 12 always

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: year,j
    real*8 :: y
    logical :: lfirst
    save lfirst
    data lfirst / .true. /

    if ( lwrite ) then
        print *,'readyrmoval: reading data as yyyy mm val'
        print *,'npermax,yrbeg,yrend = ',npermax,yrbeg,yrend
    endif
    nperyear = 12
    read(line,*,err=904,end=700) year,j,y
600 continue
    call checkvalid(year,j,y)
    if ( year < yrbeg .or. year > yrend ) then
        if ( lfirst ) then
            lfirst = .false. 
            write(0,'(a,i5)') '# disregarding year ',year
        endif
    elseif ( y < 1e33 ) then
    !**         print *,'!! data(',j,year,') = ',y
        data(j,year) = y
    endif
    read(unit,*,err=904,end=700) year,j,y
    goto 600
700 continue
    return
904 print *,'readyrmoval: error reading data of line'
    print '(a)',trim(line)
    print '(a,i4,1000g14.6)','last data read ',year,j,y
    call exit(-1)
end subroutine readyrmoval

subroutine readyrmodyval(data,npermax,yrbeg,yrend,nperyear,line &
    ,unit,lwrite)

!       format is year mon day value

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: i,j,year,month,day,dpm(12),dpm0(12)
    real :: y,xyr,xmo,xdy
    logical :: lfirst
    integer,external :: getnumwords
    save dpm,dpm0,lfirst
    data dpm0 /31,29,31,30,31,30,31,31,30,31,30,31/
    data lfirst / .true. /

    if ( lwrite ) print *,'readyrmoval: reading data as '// &
    'yyyy mm dd val'
    do month=1,12
        dpm(month) = dpm0(month)
    enddo
    nperyear = 366          ! first try
    if ( lwrite ) print *,'reading from ',trim(line)
    read(line,*,err=300,end=900) year,month,day,y
    goto 400
300 continue
    if ( lwrite ) print *,'error, trying as reals'
    read(line,*,err=905,end=900) xyr,xmo,xdy,y
    year = nint(xyr)
    month = nint(xmo)
    day = nint(xdy)
400 continue
800 continue
    if ( y == -999.9 ) goto 899
    if ( month < 1 .or. month > 12 ) then
        print *,'invalid month ',month
        goto 899
    endif
    if ( day < 1 .or. day > dpm(month) ) then
        if ( day == 30 .and. month == 2 .and. &
        data(31,year) > 1e33) then
            nperyear = 360
            do i=1,12
                dpm(i) = 30
            enddo
            do i=32,60
                data(i-1,year) = data(i,year)
            enddo
        else
            write(0,*) 'invalid day ',day
            goto 899
        endif
    endif
    j = day
    do i=1,month-1
        j = j + dpm(i)
    enddo
    if ( year < yrbeg .or. year > yrend ) then
        if ( year /= -999 ) then
            if ( lfirst ) then
                lfirst = .false. 
                write(0,'(a,i5)') '# disregarding year ',year
            endif
        endif
    elseif ( y < 1e33 ) then
    !**         print *,'data(',j,year,') = ',y,day,month
        data(j,year) = y
    endif
899 continue
8990 continue
    read(unit,'(a)',err=906,end=900) line
    if ( lwrite ) print *,'read from unit ',unit,' line ',trim(line)
    if ( line(1:1) == '#' .or. line == ' ' ) goto 8990
    if ( getnumwords(line) < 4 ) goto 8990
    read(line,*,err=915,end=900) year,month,day,y
    goto 800
915 continue
    read(line,*,err=905,end=900) xyr,xmo,xdy,y
    year = nint(xyr)
    month = nint(xmo)
    day = nint(xdy)
    goto 800
900 continue
    return
905 print *,'readseries: error reading yr,mo,dy,val data'
    print *,'from line: ',trim(line)
    call exit(-1)
906 print *,'readseries: error reading line'
    print *,'from unit ',unit
    call exit(-1)
end subroutine readyrmodyval

subroutine readyrmodyhrval(data,npermax,yrbeg,yrend,nperyear &
    ,line,unit,lwrite)

!       format is year mon day hour value

    implicit none
    integer :: npermax,yrbeg,yrend,nperyear,unit
    real :: data(npermax,yrbeg:yrend)
    logical :: lwrite
    character line*(*)
    integer :: i,j,year,month,day,hour,dpm(12),dpm0(12)
    real :: y
    logical :: lfirst
    save dpm,dpm0,lfirst
    data dpm0 /31,29,31,30,31,30,31,31,30,31,30,31/
    data lfirst / .true. /

    if ( lwrite ) print *,'readyrmoval: reading data as '// &
    'yyyy mm dd hh val'
    do month=1,12
        dpm(month) = dpm0(month)
    enddo
    nperyear = 366*24
    read(line,*,err=905,end=900) year,month,day,hour,y
800 continue
    if ( month < 1 .or. month > 12 ) then
        print *,'invalid month ',month
        goto 899
    endif
    if ( day < 1 .or. day > dpm(month) ) then
        if ( day == 30 .and. month == 2 .and. &
        data(31,year) > 1e33) then
            nperyear = 360
            do i=1,12
                dpm(i) = 30
            enddo
            do i=32,60
                data(i-1,year) = data(i,year)
            enddo
        else
            write(0,*) 'invalid day ',day
            goto 899
        endif
    endif
    if ( hour < 0 .or. hour > 24 ) then
        write(0,*) 'invalid hour ',hour
        goto 899
    endif

    j = day
    do i=1,month-1
        j = j + dpm(i)
    enddo
    j = 24*(j-1) + hour + 1
    if ( year < yrbeg .or. year > yrend ) then
        if ( year /= -999 ) then
            if ( lfirst ) then
                lfirst = .false. 
                write(0,'(a,i5)') '# disregarding year ',year
            endif
        endif
    elseif ( y < 1e33 ) then
    !**         print *,'data(',j,year,') = ',y,hour,day,month
        data(j,year) = y
    endif
899 continue
    read(unit,*,err=905,end=900) year,month,day,hour,y
    goto 800
900 continue
    return
905 print *,'readseries: error reading yr,mo,dy,hr,val data'
    print *,year,month,day,hour,y
    call exit(-1)
end subroutine readyrmodyhrval

subroutine copyheader(file,unit)

!       copy the header of time series file file to unit unit

    implicit none
    character file*(*)
    integer :: unit
    character newunits*40
    newunits = ' '
    call copyheader_newunits(file,unit,newunits)
end subroutine copyheader

subroutine copyheader_newunits(file,unit,newunits)

!       copy the header of time series file file to unit unit

    implicit none
    include 'netcdf.inc'
    integer :: mxmax,mymax,mzmax,nvmax
    parameter(mxmax=1,mymax=1,mzmax=1,nvmax=1)
    character file*(*),newunits*(*)
    integer :: unit
    integer :: i,j,k,status,nx,ny,nz,nt,firstyr,firstmo,nvars, &
    ivars(6,nvmax),ncid,nperyear,iunit
    real :: xx(mxmax),yy(mymax),zz(mzmax),undef
    character line*256,vars(nvmax)*40,lvars(nvmax)*120, &
    units(nvmax)*80,title*1000
    logical :: onlynumbers

    if ( file == ' ' ) then
        write(0,*) 'copyheader: error: empty filename'
        return
    end if
    status = nf_open(file,nf_nowrite,ncid)
    if ( status /= 0 ) then
        call rsunit(iunit)
        open(iunit,file=file)
        read(iunit,'(a)') line
        if ( onlynumbers(line) ) then
        !               no header
            close(iunit)
            return
        elseif ( line(1:1) /= '#' .and. line(2:2) /= '#' ) then
            write(unit,'(a)') trim(line)
            do i=2,5
                read(iunit,'(a)',end=800) line
                if ( onlynumbers(line) ) exit
                write(unit,'(a)') trim(line)
            enddo
        else
            write(unit,'(a)') trim(line)
            do i=1,1000
                read(iunit,'(a)',end=800) line
                if ( line(1:1) /= '#' ) exit
                if ( newunits /= ' ' ) then
                    j = index(line,'[')
                    k = index(line,']')
                    if ( j /= 0 .and. k /= 0 ) then
                        line = line(:j)//trim(newunits)//line(k:)
                    end if
                end if
                write(unit,'(a)') trim(line)
            enddo
        endif
    800 continue
        close(iunit)
    else                    ! netcdf file
        call parsenc(file,ncid,mxmax,nx,xx,mymax,ny,yy,mzmax &
        ,nz,zz,nt,nperyear,firstyr,firstmo,undef,title,nvmax,nvars &
        ,vars,ivars,lvars,units)
        status = nf_close(ncid)
        if ( newunits /= ' ' ) units = newunits
        write(unit,'(2a)') '# ',trim(title)
        write(unit,'(6a)') '# ',trim(vars(1)),' [',trim(units(1)) &
        ,'] ',trim(lvars(1))
    end if
end subroutine copyheader_newunits

subroutine yyyymmddhh(ymdh,year,month,day,hour)
    implicit none
    integer :: ymdh,year,month,day,hour
    if ( ymdh < 9999 ) then
        year = ymdh
        month = 1
        day = 1
        hour = 0
    elseif ( ymdh < 999999 ) then
        year = ymdh/100
        month = mod(ymdh,100)
        day = 1
        hour = 0
    elseif ( ymdh < 99999999 ) then
        year = ymdh/10000
        month = mod(ymdh,10000)/100
        day = mod(ymdh,100)
        hour = 0
    else
        year = ymdh/1000000
        month = mod(ymdh,1000000)/10000
        day = mod(ymdh,10000)/100
        hour = mod(ymdh,100)
    endif
    if ( month < 1 .or. month > 12 ) then
        write(0,*) 'yyyymmddhh: error: found month ',month,' in ', &
        ymdh
        call exit(-1)
    endif
    if ( day < 1 .or. day > 31 ) then
        write(0,*) 'yyyymmddhh: error: found day ',day,' in ', &
        ymdh
        call exit(-1)
    endif
    if ( hour < 0 .or. month > 24 ) then
        write(0,*) 'yyyymmddhh: error: found hour ',hour,' in ', &
        ymdh
        call exit(-1)
    endif
end subroutine yyyymmddhh

integer function getj(month,day,hour,nperyear)

!       compute index in array given a date and nperyear

    implicit none
    integer :: month,day,hour,nperyear
    integer :: j,k,dpm(12)
    data dpm /31,29,31,30,31,30,31,31,30,31,30,31/

    if ( nperyear == 1 ) then
        j = 1
    elseif ( nperyear == 4 ) then
        j = 1 + month/3
        if ( j > 4 ) j = j - 4
    elseif ( nperyear == 12 ) then
        j = month
    else
        j = day
        do k=1,month-1
            j = j + dpm(k)
        enddo
        if ( nperyear >= 24*360 ) then
            j = 24*(j-1) + hour
        else if ( nperyear >= 8*360 ) then
            j = 8*(j-1) + mod(hour,3) + 1
        else if ( nperyear >= 4*360 ) then
            j = 4*(j-1) + mod(hour,6) + 1
        else if ( nperyear >= 2*360 ) then
            j = 2*(j-1) + mod(hour,12) + 1
        elseif ( nperyear < 360 ) then
            j = 1 + (j-1)*nperyear/365
        endif
    endif
    getj = j
end function getj

subroutine adjustnperyear(nperyear,lwrite)

!       some heuristics to get one of the offically-supported values
!       (1, 4, 12, 36, 73, 360,365,366,1464)

    implicit none
    integer :: nperyear
    logical :: lwrite
    integer :: nperyearold

    nperyearold = nperyear
    if ( nperyear == 0 ) then
        nperyear = 1        ! N-yearly data is yearly
    else if ( nperyear <= 4 ) then
        if ( .false. ) print *,'do nothing to nperyear'
    else if ( nperyear <= 14 ) then
        nperyear = 12       ! monthly data
    else if ( nperyear <= 40 ) then
        nperyear = 36
    else if ( nperyear <= 350 ) then
        nperyear = 73
    else if ( nperyear < 450 ) then
        nperyear = 366
    else if ( nperyear < 1550 ) then
        nperyear = 1464
    else if ( nperyear < 10000 ) then
        nperyear = 8784
    else
        write(0,*) 'Cannot handle more than 1464 values per year'
        write(0,*) '(6-hourly data)'
        write(0,*) 'but attempted to read ',nperyear
        call exit(-1)
    end if
    if ( lwrite .and. nperyear /= nperyearold ) then
        print *,'adjustnperyear: adjusted ',nperyearold,' to ' &
        ,nperyear
    end if
end subroutine adjustnperyear

subroutine checkvalid(year,mon,val)

!       check for missing data and change to 3e33
!       note that this does NOT check for 999.9 - for too many
!       quantities his is a perfectly legal value (e.g., SLP, precip)

    implicit none
    real*8 :: val
    real :: v
    integer :: year,mon
    logical :: lwrite
    parameter (lwrite = .false. )

    v = val
    if ( lwrite) print *,'checkvalid: val = ',v,year,mon
    if ( v > 1e28 .or. v == -999.9 .or. v == -999.8 .or. &
    v == -999 .or. v == -999.99 .or. v == -9999 .or. &
    v == -888.8 ) then
        if ( v < 1e33 .and. v > -999 .and. v /= -888.8 ) &
        write(0,'(a,2i5,g20.4)')'# disregarding data point', &
        year,mon,v
        val = 3e33
        if ( lwrite) print *,'checkvalid: val invalid '
    endif
end subroutine checkvalid
