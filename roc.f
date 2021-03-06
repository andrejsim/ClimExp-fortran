        program roc
*
*       compute the ROC score from a table as spit out by verification
*
        implicit none
        integer i,ntimemax,nens,iens,itime,ntime
        real thobs,pthobs,thmod,pthmod,area
        integer,allocatable :: yrs(:),mos(:)
        real,allocatable    :: obs(:),fcst(:,:)
        logical lwrite,lsame
        character file*255,line*1024,type*4
        integer iargc,getnumwords
*
        if ( iargc().lt.3 ) then
            print *,'usage: roc {threshold|prob} threshold_obs '//
     +           'threshold_mod table [debug]'
            stop
        endif
*
*       init
*
        lwrite = .false.
        if ( iargc().ge.5 ) then
            call getarg(5,line)
            if ( line.eq.'debug' .or. line.eq.'lwrite' ) then
                lwrite =.true.
            endif
        endif
        call getarg(1,type)
        call getarg(2,file)
        call readthreshold(file,thobs,pthobs)
        call getarg(3,file)
        lsame = .false.
        if ( file(1:4).eq.'same' ) then
            if ( thobs.lt.1e30 ) then
                thmod = thobs
                pthmod = 3e33
            else
                lsame = .true.
            endif
        else
            call readthreshold(file,thmod,pthmod)
        endif
        call getarg(4,file)
        if ( lwrite ) print *,'opening ',trim(file)
        open(1,file=file,status='old')
        ntimemax = 100000
 10     continue
        read(1,'(a)') line
        if ( line(1:1).eq.'#' ) goto 10
        nens = getnumwords(line) - 3
        if ( lwrite ) print *,'found ',nens,' ensemble members'
        allocate(yrs(ntimemax))
        allocate(mos(ntimemax))
        allocate(obs(ntimemax))
        allocate(fcst(nens,ntimemax))
*
*       read data
*
        itime = 0
 100    continue
!       the format is copied from printtable.f
        itime = itime + 1
        if ( itime.gt.ntimemax ) then
            ntimemax = 2*ntimemax
            deallocate(yrs)
            deallocate(mos)
            deallocate(obs)
            deallocate(fcst)
            rewind(1)
            goto 10
        endif
        read(1,'(i4,i5,100g14.6)',end=200,err=900) yrs(itime),mos(itime)
     +       ,obs(itime),(fcst(iens,itime),iens=1,nens)
        goto 100
 200    continue
        ntime = itime - 1
        if ( lwrite ) print *,'read ',ntime,' time steps'
*
*       compute ROC curve and area under it
*
        if ( type.eq.'thre' ) then
*           vary model threshold to obtain ROC curve
            call printroc(obs,fcst,ntime,nens,thobs,pthobs,.true.,lwrite
     +           ,area)
        elseif ( type.eq.'prob' ) then
            call probroc(obs,fcst,ntime,nens,thobs,pthobs,thmod,pthmod,
     +           lsame,.true.,lwrite,area)
        else
            write(0,*) 'roc: unknown parameter ',type
            call abort
        endif
        write(0,'(a,f5.3)') 'Area under the ROC curve is ',area
*
        goto 999
 900    write(0,*) 'roc: error reading data at line ',itime
        call abort
 999    continue
        end
