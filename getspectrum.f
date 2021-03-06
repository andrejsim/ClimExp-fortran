        subroutine getspectrum(data,npermax,nperyear,yrbeg,yrend,yr1,yr2
     +       ,mens1,mens,nens1,nens2,j1,j2,avex,epx,epy,ndata,nout
     +       ,ofac,mean,yrstart,yrstop,lwrite,yr1a,yr2a)
*
*       compute a spectrum from the time series in data
*
        implicit none
        integer npermax,nperyear,yrbeg,yrend,yr1,yr2,mens1,mens,nens1
     +       ,nens2,j1,j2,avex,ndata,nout,yrstart,yrstop,yr1a,yr2a
        real data(npermax,yrbeg:yrend,0:nens2),mean
        real epx(4*ndata),epy(4*ndata),ofac,prob
        logical lwrite
        integer iens,n,n1,n2,nn,yr,mo,i,j,jmax
        integer,allocatable :: nepx(:)
        real hifac,sx,sy,somx,somy
        real,allocatable :: x(:),y(:),px(:),py(:)
        integer,external :: leap

        allocate(x(ndata))
        allocate(y(ndata))
        allocate(px(4*ndata))
        allocate(py(4*ndata))
        allocate(nepx(4*ndata))
*
*       loop over ensemble members
*       
        somx = 0
        somy = 0
        do iens=nens1,nens2
*
*           fill arrays
*       
            n = 0
            n1 = 0
            do yr=yr1-1,yr2
                do mo=j1,j2
                    j = mo
                    call normon(j,yr,i,nperyear)
                    if ( i.lt.yr1 .or. yr2.gt.yr2 ) cycle
                    if ( abs(data(j,i,iens)).lt.1e33 ) then
                        n = n + 1
                        yrstart = min(yrstart,i)
                        yrstop  = max(yrstop,i)
                        if ( nperyear.ne.366 ) then
                            x(n) = i + (j-0.5)/nperyear
                        else
                            if ( leap(i).eq.1 ) then
                                if ( j.lt.60 ) then
                                    x(n) =  i + (j-0.5)/365
                                else
                                    x(n) =  i + (j-1.5)/365
                                endif
                            else
                                x(n) = i + (j-0.5)/366
                            endif
                        endif
                        y(n) = data(j,i,iens)
                        if ( n1.eq.0 ) then
                            n1 = nperyear*i+j
                        endif
                        n2 = nperyear*i+j
                    endif
                enddo
            enddo
            if ( n.eq.0 ) then
                write(0,*) 'Spectrum: error: no valid data found'
                call abort
            end if
*       
*           compute/estimate other parameters
*       
            if ( j1.ne.j2 ) then
                hifac = real(n)/real(n2-n1+1)
            else
                hifac = real(n)/real((n2-n1)/nperyear+1)
            endif
            if ( hifac.eq.1 ) then
                ofac = 1
            else
                ofac = 4        ! see how it works
            endif
*       
*           call period (Numerical recipes p 572)
*           take care of dependent data!
*
            if ( lwrite ) then
                print *,'call Numerical Recipes period'
                print *,'x = ',(x(i),i=1,min(n,5))
                print *,'y = ',(y(i),i=1,min(n,5))
                print *,'ofac = ',ofac
                print *,'hifac = ',hifac
                print *,'4*ndata = ',4*ndata
            endif
            call period(x,y,n,ofac,hifac,px,py,4*ndata,nout,jmax,prob)
            if ( lwrite ) then
                print *,'back from period'
                print *,'px = ',(px(i),i=1,min(nout,5))
                print *,'py = ',(py(i),i=1,min(nout,5))
            end if
*
*           compute mean
*
            do i=2,nout-1
                if ( 1/px(i).gt.yr1a-yrbeg .and. 1/px(i).lt.yr2a-yrbeg )
     +               then
                    somx = somx + py(i)*(px(i+1)-px(i-1))/2
                    somy = somy + py(i)*log(px(i))*(px(i+1)-px(i-1))/2
                else if ( lwrite ) then
                    write(*,*) 'disregarding point at T=',1/px(i)
                end if
            end do
*
*           average
*       
            if ( avex.gt.1 ) then
                do i=nint(ofac),nout-avex,avex
                    sx = px(i)
                    sy = py(i)
                    do j=1,avex-1
                        sx = sx + px(i+j)
                        sy = sy + py(i+j)
                    enddo
                    n = 1+i/avex
                    px(n) = sx/avex
                    py(n) = sy/avex
                enddo
                ofac = 1+nint(ofac)/avex
                nout = n
            endif
*
*           collect ensemble informnation
*
            if ( iens.eq.nens1 ) then
                nn = nout
                do i=1,nn
                    nepx(i) = 1
                    epx(i) = px(i)
                    epy(i) = py(i)
                    if ( lwrite ) print *,i,epx(i),epy(i),nepx(i)
                enddo
            else
                do i=1,nout
                    if ( epx(i).eq.px(i) ) then
                        nepx(i) = nepx(i) + 1
                        epy(i) = epy(i) + py(i)
                        if ( lwrite ) print *,i,epx(i),epy(i),nepx(i)
                    else        ! unequal array sizes - choose nearest
                        do j=1,nn-1
                            if ( px(i).lt.(epx(j)+epx(j+1))/2 ) then
                                goto 100
                            endif
                        enddo
  100                   continue
                        epx(j) = (nepx(j)*epx(j) + px(i))/(nepx(j) + 1)
                        nepx(j) = nepx(j) + 1
                        epy(j) = epy(j) + py(i)
                        if ( lwrite ) print *,j,epx(j),epy(j),nepx(j)
                    endif
                enddo
            endif
        enddo
        do i=1,nn
            epy(i) = epy(i)/nepx(i)
            if ( lwrite ) print *,i,epx(i),epy(i),nepx(i)
        enddo
        mean = exp(-somy/somx)
        if ( lwrite ) write(*,'(a,3f16.4)') '# getspectrum: mean = '
     +       ,mean,somy,somx
        end
