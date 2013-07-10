        subroutine readcoord(unit,lon,lat,elev)
*
*       search file on unit for a line containing 'oordinates'
*       and read the coordinates from it.  Not very robust yet.
*
        implicit none
        integer unit
        real lon,lat,elev
        integer i,j
        character*80 line
*
  200   continue
        read(unit,'(a)',end=800,err=903) line
        i = index(line,'oordinates:')
        if ( i.eq.0 ) goto 200
        i = i+11
        j = index(line,'N')-1
        read(line(i:j),*) lat
        i = index(line,',') + 1
        j = index(line,'E')-1
        read(line(i:j),*) lon
        i = i + index(line(i:),',') + 1
        j = index(line,'m')-1
        if ( j.lt.i ) then
            elev = -999
        else
            read(line(i:j),*) elev
        endif
        return
  800   continue
        lon = 3e33
        lat = 3e33
        return
  903   print *,'stationlist: error: error reading in file'
        call abort
        end

        subroutine readcodename(line,code,name,lwrite)
*
*       read the code and name from line in getstation format: 
*       ^[^:]*: code name$
*
        implicit none
        character line*(*),code*(*),name*(*)
        logical lwrite
        integer i,j
*
        i = index(line,':')
  210   continue
        i = i+1
        if ( line(i:i).eq.' ' ) goto 210
        j = i
  220   continue
        j = j+1
        if ( line(j:j).ne.' ' ) goto 220
        code = line(i:j-1)
        if ( lwrite ) print *,'readcodename: found code ',trim(code)
        goto 226
  225   continue
        print *, 'readcodename: error reading code from ',line(i:j-1)
        print *, line
  226   continue
        i = j
  230   continue
        i = i+1
        if ( line(i:i).eq.' ' ) goto 230
        name = line(i:)
        do j=1,len(name)
            if ( name(j:j).eq.';' .or. name(j:j).eq.'`' .or.
     +           name(j:j).eq.'"' .or. name(j:j).eq.'''' .or. 
     +           name(j:j).eq.'&' .or. name(j:j).eq.'|' .or. 
     +           name(j:j).eq.'%' .or. name(j:j).eq.'<' .or. 
     +           name(j:j).eq.'>') name(j:j) = ' '
            if ( name(j:j).eq.'(' .or. name(j:j).eq.')' ) name(j:j)='/'
        enddo
        end

        subroutine checkval(retval,command)
        implicit none
        integer retval
        character command*(*)
        integer llen
        external llen
        if ( retval.ne.0 ) then
            write(0,*) 'error ',retval,' in '
            write(0,*) command(1:llen(command))
            write(*,*) 'error ',retval,' in '
            write(*,*) command(1:llen(command))
            call abort
        endif
        end
