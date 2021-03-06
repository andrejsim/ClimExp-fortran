        program runningmoments
*
*       analyse running mean, s.d., skew, ... of timeseries
*
        implicit none
#include "param.inc"
#include "getopts.inc"
        integer nboot
        parameter (nboot=799)
        integer i,ii,j,nperyear,imom,iens,mens1,mens,n,yr,j1,j2,mboot
     +       ,yrmin,yrmax,iboot,iran,yr1s,yr2s,ndatens
        real,allocatable :: data(:,:,:),xx(:),yy(:)
        real result(0:nboot),rmin(0:nboot),rmax(0:nboot),rdif(0:nboot)
     +       ,ave,adev,sdev,sd2,skew,curt,ave1,adev1,sdev1,sd21,skew1
     +       ,curt1,signmin,signmax,signdif,noise,alpha
        logical first
        character file*255,string*100,momentvar*4,var*40,units*20
        integer iargc
        real gasdev
        external gasdev
        data iran /0/
*
        n = iargc()
        if ( n.lt.2 ) then
            print *,'usage: runningmoments timeseries ',
     +            '1|2|3|ave|sd|skew runw n outfile [options]'
            stop
        endif
*
        call getarg(1,file)
        print '(2a)','# file ',file(1:index(file,' ')-1)
        allocate(data(npermax,yrbeg:yrend,0:nensmax))
        call readensseries(file,data,npermax,yrbeg,yrend,nensmax
     +       ,nperyear,mens1,mens,var,units,lstandardunits,lwrite)
        call getarg(2,string)
        if ( string(1:3).eq.'mea' .or. string(1:3).eq.'ave' .or.
     +        string(1:1).eq.'1' ) then
            imom = 1
        elseif ( string(1:2).eq.'sd' .or. string(1:4).eq.'s.d.' .or.
     +           string(1:3).eq.'momentvar' .or.string(1:1).eq.'2' )
     +           then
            imom = 2
        elseif ( string(1:3).eq.'ske' .or.
     +            string(1:1).eq.'3' ) then
            imom = 3
        elseif ( string(1:4).eq.'curt' .or.
     +            string(1:1).eq.'4' ) then
            imom = 4
        else
            write(0,*) 'runningmoments: unknown moment ',string
            call abort
        endif
        call getopts(3,n,nperyear,yrbeg,yrend,.true.,mens1,mens)
        if ( mens.gt.0 ) then
            print '(a,i3,a,i3)','# Using ensemble members ',nens1,' to '
     +            ,nens2
        endif
        if ( nyrwindow.le.0 ) then
            write(0,*) 'runningmoments: please specify running ',
     +            'window length >0, not ',nyrwindow
            call abort
        endif
*
*       sum series
*       
        do iens=nens1,nens2
            if ( lsum.gt.1 ) then
                if ( iens.eq.nens1 ) print '(a,i4,a)'
     +                ,'# summing over ',lsum,' periods'
                call sumit(data(1,yrbeg,iens),npermax,nperyear
     +                ,yrbeg,yrend,lsum,oper)
                decor = max(decor,real(lsum-1))
            endif
*       
*           apply minindx, maxindx cuts
*       
            if ( maxindx.lt.1e33 .or. minindx.gt.-1e33 ) then
                do i=yr1,yr2
                    do j=1,nperyear
                        if (  data(j,i,iens).gt.maxindx .or.
     +                        data(j,i,iens).lt.minindx ) then
                            data(j,i,iens) = 3e33
                        endif
                    enddo
                enddo
            endif
*       
*           log, sqrt
*
            if ( logscale ) then
                if ( iens.eq.nens1 ) print '(a)'
     +                ,'# taking logarithm'
                call takelog(data(1,yrbeg,iens),npermax
     +                ,nperyear,yrbeg,yrend)
            endif
            if ( sqrtscale ) then
                if ( iens.eq.nens1 ) print '(a)','# taking sqrt'
                call takesqrt(data(1,yrbeg,iens),npermax
     +                ,nperyear,yrbeg,yrend)
            endif
            if ( squarescale ) then
                if ( iens.eq.nens1 ) print '(a)','# taking square'
                call takesquare(data(1,yrbeg,iens),npermax
     +                ,nperyear,yrbeg,yrend)
            endif
*       
*           differentiate data
*
            if ( ndiff.ne.0 ) then
                if ( iens.eq.nens1 ) print '(a,i4)'
     +                ,'# taking differences/averaging ',ndiff
                call diffit(data(1,yrbeg,iens),npermax,nperyear
     +                ,yrbeg,yrend,ndiff)
            endif
*       
*           anomalies - necessary if we consider more than one month
*       
            if ( anom ) then
                if ( iens.eq.nens1 ) print '(a)'
     +                ,'# taking anomalies'
                call anomal(data(1,yrbeg,iens),npermax,nperyear
     +                ,yrbeg,yrend,yr1,yr2)
            endif
        enddo
!
!       anomalies wrt ensemble mean
!
        if ( lensanom .and. nens1.ne.nens2 ) then
            if ( lwrite ) print '(a)'
     +           ,'# taking anomalies wrt ensemble mean'
            call anomalensemble(data,npermax,nperyear,yrbeg,
     +           yrend,yr1,yr2,nens1,nens2)
        endif
*       
*       overall moment
*       
        call getj1j2(j1,j2,m1,nperyear,.true.)
        if ( minnum.le.0 ) then
            minnum = nint(0.8*nyrwindow)
            write(14,'(a,i6,a,i6,a)') '# Demanding at least ',minnum
     +           ,' years in a sliding window of ',nyrwindow,' years'
        endif
        n=0
        first = .true.
        ndatens = nperyear*(yr2-yr1+1)*(nens2-nens1+1)
        allocate(xx(ndatens))
        allocate(yy(ndatens))
        do iens=nens1,nens2
            do i=yr1-1,yr2+1
                do j=j1,j2
                    call normon(j,i,ii,nperyear)
                    if ( ii.lt.yr1 .or. ii.gt.yr2 ) goto 600
                    if ( data(j,ii,iens).lt.1e33 ) then
                        if ( first ) then
                            first = .false.
                            yrmin = i
                        endif
                        yrmax = i
                        n = n + 1
                        if ( n.gt.ndatens ) goto 901
                        xx(n) = data(j,ii,iens)
                    endif
  600               continue
                enddo
            enddo
        enddo
        yr1 = max(yrmin,yr1)
        yr2 = min(yrmax,yr2)
        if ( n.lt.minnum*(j2-j1+1)*(nens2-nens1+1) ) then
            if ( lwrite ) print *,'not enough points: ',
     +            n,minnum
            goto 900
        endif
        if ( lwrite ) print *,'analysing ',n,' points'
        call moment(xx,n,ave,adev,sdev,sd2,skew,curt)
        call bootmoment(imom,xx,yy,n,nboot,decor,result)
        if ( imom.eq.1 ) then
            momentvar = 'mean'
        elseif ( imom.eq.2 ) then
            momentvar = 's.d.'
        elseif ( imom.eq.3 ) then
            momentvar = 'skew'
        elseif ( imom.eq.4 ) then
            momentvar = 'curt'
        else
            momentvar = '????'
        endif
        if ( lweb ) then
            write(14,'(a)') '# <table class="realtable" '//
     +           'border=0 cellpadding=0 cellspacing=0>'//
     +           '<tr><th>moment</th><th>value</th>'//
     +           '<th>95% CI</th>'
            write(14,'(3a,g20.4,a,g20.4,a,g20.4,a,g20.4,a)') 
     +           '# <tr><td>',momentvar,'</td><td>',result(0),
     +           '</td><td>',
     +           result(nint(real(nboot+1)*0.025)),'...',
     +           result(nint(real(nboot+1)*0.975)),
     +           '</td></tr></table>'
        else
            write(14,'(7a)') '# moment ',
     +           '            mean    ',
     +           '            2.5%    ',
     +           '             17%    ',
     +           '             50%    ',
     +           '             83%    ',
     +           '           97.5%    '
            write(14,'(3a,6g20.6)') '# ',momentvar,' = ',result(0),
     +           result(nint(real(nboot+1)*0.025)),
     +           result(nint(real(nboot+1)*0.17)),
     +           result(nint(real(nboot+1)*0.5)),
     +           result(nint(real(nboot+1)*0.83)),
     +           result(nint(real(nboot+1)*0.975))
        endif
*
*       running window analysis
*
        rmin(0) = +3e33
        rmax(0) = -3e33
        do yr=yr1-1,yr2-nyrwindow+1
            call keepalive(yr-yr1+1,yr2-yr1-nyrwindow+2)
            n = 0
            do iens=nens1,nens2
                yr1s = max(yr1,yr)
                yr2s = min(yr2,yr+nyrwindow-1)
                do i=yr1s-1,yr2s
                    do j=j1,j2
                        call normon(j,i,ii,nperyear)
                        if ( ii.lt.yr1s .or. ii.gt.yr2s ) goto 700
                        if ( data(j,ii,iens).lt.1e33 ) then
                            n = n + 1
                            xx(n) = data(j,ii,iens)
                        endif
  700                   continue
                    enddo
                enddo
            enddo
            if ( n.lt.minnum*(j2-j1+1)*(nens2-nens1+1) ) then
                if ( lwrite ) print *,'not enough points: ',
     +                n,minnum
                goto 800
            endif
            mboot = (nboot+1)/2-1
            call bootmoment(imom,xx,yy,n,mboot,decor,result)
            if ( lwrite ) then
                print *,'with ',n,' points in ',yr1s,yr2s,' found '
     +               ,result(0)
            end if
            rmin(0) = min(rmin(0),result(0))
            rmax(0) = max(rmax(0),result(0))
            write(14,'(i4,6g20.6)') yr+nyrwindow/2,result(0),
     +        result(nint(real(mboot+1)*0.025)),
     +        result(nint(real(mboot+1)*0.17)),
     +        result(nint(real(mboot+1)*0.5)),
     +        result(nint(real(mboot+1)*0.83)),
     +        result(nint(real(mboot+1)*0.975))
  800       continue
        enddo
        rdif(0) = rmax(0)-rmin(0)
*
*       MC test on significance of variations
*
        print '(a)'
     +       ,'#<br>For overall significance disregarding nonzero '/
     +       /'skewness and curtosis for the moment.'
        if ( decor.eq.0 ) then
            alpha = 0
        else
            alpha = exp(-1/decor)
        endif
        do iboot=1,nboot
            call keepalive(iboot,nboot)
            do iens=nens1,nens2
                noise = gasdev(iran)
                do i=yr1,yr2
                    do j=1,nperyear
                        noise = alpha*noise
     +                       + sqrt(1-alpha**2)*gasdev(iran)
                        if ( data(j,i,iens).lt.1e33 ) then
                            data(j,i,iens) = ave + sdev*noise
                        endif
                    enddo
                enddo
            enddo
            rmin(iboot) = +3e33
            rmax(iboot) = -3e33
            do yr=yr1,yr2-nyrwindow+1
                n = 0
                do iens=nens1,nens2
                    yr1s = max(yr1,yr)
                    yr2s = min(yr2,yr+nyrwindow-1)
                    do i=yr1s-1,yr2s
                        do j=j1,j2
                            call normon(j,i,ii,nperyear)
                            if ( ii.lt.yr1s .or. ii.gt.yr2s ) goto 850
                            if ( data(j,ii,iens).lt.1e33 ) then
                                n = n + 1
*                               should include higher moments RSN
                                xx(n) = data(j,ii,iens)
                            endif
 850                        continue
                        enddo
                    enddo
                enddo
                if ( n.lt.minnum*(j2-j1+1)*(nens2-nens1+1) ) then
                    if ( lwrite ) print *,'not enough points: ',
     +                   n,minnum
                    goto 890
                endif
                call moment(xx,n,ave1,adev1,sdev1,sd21,skew1,curt1)
                call getmoment(imom,xx,n,result(0))
                rmin(iboot) = min(rmin(iboot),result(0))
                rmax(iboot) = max(rmax(iboot),result(0))
 890            continue
            enddo
            rdif(iboot) = rmax(iboot)-rmin(iboot)
        enddo
        if ( decor.eq.0 ) then
            print '(a)','# Assuming all data points are independent'
        else
            print '(a,f5.1)','# Assuming a decorrelation length of '
     +           ,decor
        endif
        print '(2a,i6,a)','# Significances are computed'
     +       ,' against a ',nboot,' sample Monte Carlo.'
        if ( lweb) print '(a)','<table class="realtable" '//
     +       'border=0 cellpadding=0 cellspacing=0>'//
     +       '<tr><th colspan=3>Probability that the distribution is '//
     +       '<br>a chance fluctuation around a constant'//
     +       '<tr><th>statistic</th><th>value</th><th>'//
     +       'p-value</th></tr>'
        call getsign('minimum',rmin(0),rmin(1),nboot,-1,signmin,.true.)
        call getsign('maximum',rmax(0),rmax(1),nboot,1,signmax,.true.)
        call getsign('difference',rdif(0),rdif(1),nboot,1,signdif,.true.
     +       )
        if ( lweb) print '(a)','</table>'
*
 900    continue
        goto 999
 901    write(0,*) 'runningmoments: error: too many points, ',
     +        'increase ndatens (currently',ndatens,')'
        call abort
 999    continue
        end
