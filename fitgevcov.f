*  #[ fitgevcov:
        subroutine fitgevcov(xx,yrs,ntot,a,b,xi,alpha,beta,j1,j2
     +       ,lweb,ntype,lchangesign,yr1a,yr2a,xyear,cov1,cov2,offset
     +       ,t,t25,t975,tx,tx25,tx975,inrestrain,assume
     +       ,lboot,lprint,plot,lwrite)
*
*       fit a GEV distribution to the data, which is already assumed to be block max
*       input:
*       xx(2,ntot) data,covariate
*       j1,j2    use days/months/... j1 to j2
*       year     leave out this year from teh fit and compute return time for it
*       xyear    value for year, has been set to undef in the series
*       inrestrain restrain xi parameter by adding a normal distribution of width 0.5*inrestrain to the cost function
*       assume   shift: only vary a, scale: vary a & b in unison, both: independently
*       output
*       a,b,xi,alpha,beta  parameters of fit
*       assume   shift: alpha modifies the position parameter a(cov) = a + alpha*cov
*                scale: alpha modifies both the position and shape parameters:
*                       a(cov) = a*exp(alpha*cov), b(cov) = b*exp(alpha*cov)
*                both:  a(cov) = a + alpha*cov, b(cov) = b + beta*cov
*       t(10,3)    return values for 10, 20, 50, ..., 10000 years for cov=cov1,cov2 and the difference
*       t25,t975   2.5%, 97.5% quantiles of these return values
*       tx(3)      return time of the value of year (xyear) in the context of the other values and difference
*       tx25,tx975 2.5%, 97.5% quantiles of these return times and their differences
*
        implicit none
*
        integer nmc
        parameter(nmc=1000)
        integer ntot,j1,j2,ntype,yr1a,yr2a
        integer yrs(0:ntot)
        real xx(2,ntot),a,b,xi,alpha,beta,xyear,cov1,cov2,offset,
     +       inrestrain,t(10,3),t25(10,3),t975(10,3),
     +       tx(3),tx25(3),tx975(3),ttt(10,3),txtxtx(3)
        character*(*) assume
        logical lweb,lchangesign,lboot,lprint,plot,lwrite
*
        integer i,j,k,l,n,nx,iter,iens,nfit,year
        real x,aa(nmc),bb(nmc),xixi(nmc),alphaalpha(nmc),betabeta(nmc)
     +       ,tt(nmc,10,3),b25,b975,xi25,xi975,alpha25,alpha975
     +       ,beta25,beta975,t5(10,3),t1(10,3)
     +       ,db,dxi,f,threshold,thens,z,ll,ll1,txtx(nmc,3)
     +       ,a25,a975,ranf,mean,sd,dalpha,dbeta
     +       ,mindata,minindx,pmindata,snorm,s,xxyear,frac
        real adev,var,skew,curt,aaa,bbb,siga,chi2,q
        real,allocatable :: yy(:),ys(:),zz(:),sig(:)
        character lgt*4
*
        integer nmax,ncur
        parameter(nmax=100000)
        real data(2,nmax),restrain
        logical llwrite
        common /fitdata3/ data
        common /fitdata2/ restrain,ncur,llwrite
        character cassume*5
        common /fitdata4/ cassume
*
        real llgevcov,gevcovreturnlevel,gevcovreturnyear
        external llgevcov,gevcovreturnlevel,gevcovreturnyear
*
        year = yr2a
        if ( lwrite ) then
            print *,'fitgevcov: input:'
            print *,'assume         = ',assume
            print *,'j1,j2          = ',j1,j2
            print *,'year,xyear     = ',year,xyear
            print *,'cov1,cov2,offset ',cov1,cov2,offset
            if ( .true. ) then
                do i=1,ntot
                    print *,i,(xx(j,i),j=1,2)
                enddo
            endif
        endif
*
*       compute first-guess parameters
*
        allocate(yy(ntot))
        allocate(ys(ntot))
        allocate(zz(ntot))
        allocate(sig(ntot))
        do i=1,ntot
            yy(i) = xx(1,i)
            zz(i) = xx(2,i)
        end do
        sig = 0
        call moment(yy,ntot,mean,adev,sd,var,skew,curt)
        call fit(zz,yy,ntot,sig,0,aaa,alpha,siga,dalpha,chi2,q)
        if ( lwrite ) then
            print *,'fitgevcov: computed initialisation values:'
            print *,'mean,sd,alpha,dalpha = ',mean,sd,alpha,dalpha
        end if
*
*       ill-defined case
*
        if ( sd.eq.0 ) then
            a = 3e33
            b = 3e33
            xi = 3e33
            alpha = 3e33
            beta = 3e33
            t = 3e33
            t25 = 3e33
            t975 = 3e33
            tx = 3e33
            tx25 = 3e33
            tx975 = 3e33
            return
        endif
*
*       copy to common for routine llgevcov
*
        ncur = ntot
        do i=1,ncur
            data(:,i) = xx(:,i)
        enddo
        restrain = inrestrain
        llwrite = lwrite
        cassume = assume

        b = sd*sqrt(6.)/(4*atan(1.))
        a = mean - 0.57721*b
        xi = 0
        if ( assume.eq.'shift' .or. assume.eq.'scale' ) then
            beta = 3e33
            call fit1gevcov(a,b,xi,alpha,dalpha,iter)
        else if ( assume.eq.'both' ) then
            beta = alpha
            dbeta = dalpha
            call fit2gevcov(a,b,xi,alpha,beta,dalpha,dbeta,iter)
        else
            write(0,*) 'fitgevcov: error: unknown value for assume ',
     +           assume
        end if
        call getreturnlevels(a,b,xi,alpha,beta,cov1,cov2,
     +       gevcovreturnlevel,j1,j2,t)
        if ( xyear.lt.1e33 ) then
            call getreturnyears(a,b,xi,alpha,beta,xyear,cov1,cov2,
     +           gevcovreturnyear,j1,j2,tx,lwrite)
        endif
*
*       bootstrap to find error estimates
*
        if ( .not.lboot ) then
            if ( lchangesign ) then
                a = -a
                b = -b
                t = -t
                alpha = -alpha
                if ( cassume.eq.'both' ) then
                    beta = -beta
                end if
            endif
            return
        endif
        if ( .not.lweb ) print '(a,i6,a)','# doing a ',nmc
     +        ,'-member bootstrap to obtain error estimates'
        do iens=1,nmc
            if ( .not.lweb .and. mod(iens,100).eq.0 )
     +           print '(a,i6)','# ',iens
            do i=1,ntot
                call random_number(ranf)
                j = 1+int(ntot*ranf)
                if ( j.lt.1 .or. j.gt.ntot ) then
                    write(0,*) 'fitgev: error: j = ',j
                    call abort
                endif
                data(:,i) = xx(:,j)
            enddo
            aa(iens) = a
            bb(iens) = b
            xixi(iens) = xi
            alphaalpha(iens) = alpha
            llwrite = .false.
            if ( assume.eq.'shift' .or. assume.eq.'scale' ) then
                betabeta(iens) = 3e33
                call fit1gevcov(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),dalpha,iter)
            else if ( assume.eq.'both' ) then
                betabeta(iens) = beta
                call fit2gevcov(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),betabeta(iens),dalpha,dbeta,iter)
            else
                write(0,*) 'fitgevcov: error: unknown value for assume '
     +               ,assume
            end if
            call getreturnlevels(aa(iens),bb(iens),xixi(iens),
     +           alphaalpha(iens),betabeta(iens),
     +           cov1,cov2,gevcovreturnlevel,j1,j2,ttt)
            do i=1,10
                do j=1,3
                    tt(iens,i,j) = ttt(i,j)
                end do
            end do
            if ( xyear.lt.1e33 ) then
                call getreturnyears(aa(iens),bb(iens),xixi(iens),
     +               alphaalpha(iens),betabeta(iens),xyear,cov1,cov2,
     +               gevcovreturnyear,j1,j2,txtxtx,lwrite)
                do j=1,3
                    txtx(iens,j) = txtxtx(j)
                end do
            endif
        enddo
        if ( lchangesign ) then
            a = -a
            aa = -aa
            b = -b
            bb = -bb
            alpha = -alpha
            alphaalpha = -alphaalpha
            if ( assume.eq.'both' ) then
                beta = -beta
                betabeta = -betabeta
            end if
            t = -t
            tt = -tt
        endif
        call getcut( a25, 2.5,nmc,aa)
        call getcut(a975,97.5,nmc,aa)
        call getcut( b25, 2.5,nmc,bb)
        call getcut(b975,97.5,nmc,bb)
        call getcut( xi25, 2.5,nmc,xixi)
        call getcut(xi975,97.5,nmc,xixi)
        call getcut( alpha25, 2.5,nmc,alphaalpha)
        call getcut(alpha975,97.5,nmc,alphaalpha)
        if ( assume.eq.'both' ) then
            call getcut( beta25, 2.5,nmc,betabeta)
            call getcut(beta975,97.5,nmc,betabeta)
        end if
        do i=1,10
            do j=1,3
                if ( lchangesign ) then
                    lgt = '&lt;'
                    call getcut(t5(i,j),5.,nmc,tt(1,i,j))
                    call getcut(t1(i,j),1.,nmc,tt(1,i,j))
                else
                    lgt = '&gt;'
                    call getcut(t5(i,j),95.,nmc,tt(1,i,j))
                    call getcut(t1(i,j),99.,nmc,tt(1,i,j))
                endif
                call getcut(t25(i,j),2.5,nmc,tt(1,i,j))
                call getcut(t975(i,j),97.5,nmc,tt(1,i,j))
            enddo
        end do
        do j=1,3
            if ( xyear.lt.1e33 ) then
                call getcut(tx25(j), 2.5,nmc,txtx(1,j))
                call getcut(tx975(j),97.5,nmc,txtx(1,j))
                if ( lchangesign ) xyear = -xyear
            endif
        end do
*
*       output
*
        if ( .not.lprint .and. .not.lwrite ) return
        if ( lweb ) then
            print '(a)','# <tr><td colspan="4">Fitted to GEV '//
     +           'distribution P(x) = exp(-(1+&xi;(x-a'')'//
     +               '/b'')^(-1/&xi;))</td></tr>'
            call printab(lweb)
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           'a:</td><td>',a-alpha*offset,'</td><td>',
     +           a25-alpha*offset,'...',a975-alpha*offset,'</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           'b:</td><td>',b,'</td><td>',b25,'...',
     +           b975,'</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           '&xi;:</td><td>',xi,'</td><td>',xi25,'...',xi975,
     +           '</td></tr>'
            print '(a,f16.3,a,f16.3,a,f16.3,a)','# <tr><td colspan=2>'//
     +           '&alpha;:</td><td>',alpha,'</td><td>',alpha25,'...',
     +           alpha975,'</td></tr>'
            if ( assume.eq.'both' ) then
                print '(a,f16.3,a,f16.3,a,f16.3,a)',
     +               '# <tr><td colspan=2>&beta;:</td><td>',beta,
     +               '</td><td>',beta25,'...',beta975,'</td></tr>'
            end if
        else
            print '(a,i5,a)','# Fitted to GEV distribution in ',iter
     +           ,' iterations'
            print '(a)','# P(x) = exp(-(1+xi*(x-a''/b'')**'//
     +           '(-1/xi)) with'
            call printab(lweb)
            print '(a,f16.3,a,f16.3,a,f16.3)','# a = ',a,' \\pm ',a975
     +           -a25
            print '(a,f16.3,a,f16.3,a,f16.3)','# b = ',b,' \\pm ',b975
     +           -b25
            print '(a,f16.3,a,f16.3,a,f16.3)','# xi  = ',xi,' \\pm ',
     +           xi975-xi25
            print '(a,f16.3,a,f16.3,a,f16.3)','# alpha ',alpha,' \\pm ',
     +           alpha975-alpha25
            if ( assume.eq.'both' ) then
                print '(a,f16.3,a,f16.3,a,f16.3)','# beta  ',beta,
     +               ' \\pm ',beta975-beta25
            end if
        end if
        call printcovreturnvalue(ntype,t,t25,t975,yr1a,yr2a,lweb)
        call printcovreturntime(year,xyear,tx,tx25,tx975,yr1a,yr2a,lweb)

        if ( plot ) then
            call plot_tx_cdfs(txtx,nmc,ntype)
        end if

        ! no cuts
        mindata = -2e33
        minindx = -2e33
        pmindata = -1
        snorm = 1
        frac = 1
        ! GEV fit
        nfit = 5

        ! compute distribution at past year and plot it
        call adjustyy(ntot,xx,assume,a,b,alpha,beta,cov1,
     +       yy,zz,aaa,bbb,lchangesign,lwrite)
        ys(1:ntot) = yy(1:ntot)
        print '(a,i5)','# distribution in year ',yr1a
        call plotreturnvalue(ntype,t25(1,1),t975(1,1),j2-j1+1)
        call plot_ordered_points(yy,ys,yrs,ntot,ntype,nfit,
     +       frac,aaa,bbb,xi,j1,j2,minindx,mindata,pmindata,
     +       year,xyear,snorm,lchangesign,lwrite,.false.)

        ! compute distribution at present year and plot it
        call adjustyy(ntot,xx,assume,a,b,alpha,beta,cov2,
     +       yy,zz,aaa,bbb,lchangesign,lwrite)
        ys(1:ntot) = yy(1:ntot)
        print '(a)'
        print '(a)'
        print '(a,i5)','# distribution in year ',yr2a
        call plotreturnvalue(ntype,t25(1,2),t975(1,2),j2-j1+1)
        call plot_ordered_points(yy,ys,yrs,ntot,ntype,nfit,
     +       frac,aaa,bbb,xi,j1,j2,minindx,mindata,pmindata,
     +       year,xyear,snorm,lchangesign,lwrite,.true.)

        end
*  #] fitgevcov:
*  #[ fit1gevcov:
        subroutine fit1gevcov(a,b,xi,alpha,dalpha,iter)
        implicit none
        integer iter
        real a,b,xi,alpha,dalpha
        integer i
        real q(5),p(5,4),y(5),tol
        real llgevcov
        external llgevcov
*
        q(1) = a
        q(2) = b
        q(3) = xi
        q(4) = alpha
        q(5) = 3e33
        p(1,1) = q(1) *0.9
        p(1,2) = q(2) *0.9
        p(1,3) = q(3) *0.9
        p(1,4) = q(4) - dalpha
        p(2,1) = p(1,1) *1.2
        p(2,2) = p(1,2)
        p(2,3) = p(1,3)
        p(2,4) = p(1,4)
        p(3,1) = p(1,1)
        p(3,2) = p(1,2) *1.2
        p(3,3) = p(1,3)
        p(3,4) = p(1,4)
        p(4,1) = p(1,1)
        p(4,2) = p(1,2)
        p(4,3) = p(1,3) *1.2 + 0.1
        p(4,4) = p(1,4)
        p(5,1) = p(1,1)
        p(5,2) = p(1,2)
        p(5,3) = p(1,3)
        p(5,4) = p(1,4) + 2*dalpha
        do i=1,5
            q(1) = p(i,1)
            q(2) = p(i,2)
            q(3) = p(i,3)
            q(4) = p(i,4)
            y(i) = llgevcov(q)
        enddo
        tol = 1e-4
        call amoeba(p,y,5,4,4,tol,llgevcov,iter)
*       maybe add restart later
        a = p(1,1)
        b = abs(p(1,2))
        xi = p(1,3)
        alpha = p(1,4)
        end
*  #] fit1gevcov:
*  #[ fit2gevcov:
        subroutine fit2gevcov(a,b,xi,alpha,beta,dalpha,dbeta,iter)
        implicit none
        integer iter
        real a,b,xi,alpha,beta,dalpha,dbeta
        integer i
        real q(5),p(6,5),y(6),tol
        real llgevcov
        external llgevcov
*
        q(1) = a
        q(2) = b
        q(3) = xi
        q(4) = alpha
        q(5) = beta
        p(1,1) = q(1) *0.9
        p(1,2) = q(2) *0.9
        p(1,3) = q(3) *0.9
        p(1,4) = q(4) - dalpha
        p(1,5) = q(5) - dbeta
        p(2,1) = p(1,1) *1.2
        p(2,2) = p(1,2)
        p(2,3) = p(1,3)
        p(2,4) = p(1,4)
        p(2,5) = p(1,5)
        p(3,1) = p(1,1)
        p(3,2) = p(1,2) *1.2
        p(3,3) = p(1,3)
        p(3,4) = p(1,4)
        p(3,5) = p(1,5)
        p(4,1) = p(1,1)
        p(4,2) = p(1,2)
        p(4,3) = p(1,3) *1.2 + 0.1
        p(4,4) = p(1,4)
        p(4,5) = p(1,5)
        p(5,1) = p(1,1)
        p(5,2) = p(1,2)
        p(5,3) = p(1,3)
        p(5,4) = p(1,4) + 2*dalpha
        p(5,5) = p(1,5)
        p(6,1) = p(1,1)
        p(6,2) = p(1,2)
        p(6,3) = p(1,3)
        p(6,4) = p(1,4)
        p(6,5) = p(1,5) + 2*dbeta
        do i=1,6
            q(1) = p(i,1)
            q(2) = p(i,2)
            q(3) = p(i,3)
            q(4) = p(i,4)
            q(5) = p(i,5)
            y(i) = llgevcov(q)
        enddo
        tol = 1e-4
        call amoeba(p,y,6,5,5,tol,llgevcov,iter)
*       maybe add restart later
        a = p(1,1)
        b = abs(p(1,2))
        xi = p(1,3)
        alpha = p(1,4)
        beta = p(1,5)
        end
*  #] fit1gevcov:
*  #[ llgevcov:
        real function llgevcov(p)
*
*       computes the log-likelihood function for a covariant-dependent GEV distribution
*       with parameters a,b,xi,alpha=p(1-4) and data in common.
*
        implicit none
*
        real p(5)
*
        integer i
        real x,z,xi,s,aa,bb
*
        integer nmax,ncur
        parameter(nmax=100000)
        real data(2,nmax),restrain
        logical llwrite
        common /fitdata3/ data
        common /fitdata2/ restrain,ncur,llwrite
        character cassume*5
        common /fitdata4/ cassume
*
        llgevcov = 0
        if ( abs(p(3)).gt.10 ) then
            llgevcov = 3e33
            goto 999
        endif
        if ( restrain.lt.0 ) then
            write(0,*) 'llgevcov: restrain<0 ',restrain
            call abort
        end if
        do i=1,ncur
            call getabfromcov(p(1),p(2),p(4),p(5),data(2,i),aa,bb)
            if ( abs(bb).lt.1e-30 ) then
                llgevcov = 3e33
                goto 999
            end if
            z = (data(1,i)-aa)/bb
            xi = p(3)
            if ( abs(xi).lt.1e-4 ) then
                if ( -z+xi*z**2/2.gt.log(3e33) ) then
                    llgevcov = 3e33
                    goto 999
                end if
                s = - exp(-z+xi*z**2/2) - z*(1+xi-xi*z/2)
            else
                if ( 1+xi*z.le.0 ) then
***                 write(0,*) 'GEV undefined',(1+xi*z)
                    llgevcov = 3e33
                    goto 999
                else if ( -log(1+xi*z)/xi.gt.log(3e33) ) then
                    ! too large...
                    llgevcov = 3e33
                    goto 999
                else
                    s = - (1+1/xi)*log(1+xi*z)
     +                   - (1+xi*z)**(-1/xi)
                endif
            endif
            s = s - log(abs(bb))
            llgevcov = llgevcov + s            
            if ( .false. .and. llwrite ) then
                print *,i,data(1,i),aa,bb,xi,z,-s,-llgevcov
            end if
        enddo
*       normalization is not 1 in case of cut-offs
        call gevcovnorm(p(1),p(2),p(3),p(4),p(5),s)
        if ( s.lt.1e33 ) then
            llgevcov = llgevcov - ncur*log(s)
        else
            llgevcov = 3e33
            goto 999
        end if
        if ( restrain.ne.0 ) then
*           preconditioning on xi with gaussian of width restrain/2
*           around 0
            llgevcov = llgevcov - (xi/(restrain/2))**2/2
        endif
*       minimum, not maximum
        llgevcov = -llgevcov
*
  999   continue
        if ( llwrite ) print *,'a,b,xi,alpha,llgevcov = ',
     +       p(1),p(2),p(3),p(4),llgevcov
        end
*  #] llgevcov:
*  #[ gevcovnorm:
        subroutine gevcovnorm(a,b,xi,alpha,beta,s)
        implicit none
	include "getopts.inc"
        real a,b,xi,alpha,beta,s
        real z1,z2

        if ( minindx.gt.-1e33 .or. maxindx.lt.1e33 ) then
            write(0,*) 'gevcovnorm: boundaries not yet avaiable for '//
     +           'fit of GEV(t)'
            call abort
        else
            s = 1
        endif
***        print *,'gevcovnorm: norm = ',a,b,s
        end
*  #] gevcovnorm:
*  #[ gevcovreturnlevel:
        real function gevcovreturnlevel(a,b,xi,alpha,beta,x,cov)
!
!       compute return times given the GEV distribution parameters a,b,xi and 
!       x = log10(returntime) for covariant cov and fit parameter alpha
!       Uses a few Taylor series approximation for xi small and/or return time large
!
        implicit none
        real a,b,xi,alpha,beta,x,cov
        real aa,bb,y,t
        call getabfromcov(a,b,alpha,beta,cov,aa,bb)
        if ( abs(xi).gt.10 ) then
            gevcovreturnlevel = 3e33
        else if ( abs(xi).lt.1e-4 ) then
            if ( x.le.8 ) then
                y = log(-log(1-dble(10)**(dble(-x))))
            else
                y = -x*log(10.)
            end if
            t = aa - bb*y + bb*xi/2*y**2
        else
            if ( x.le.8 ) then
                t = aa - bb/xi*(1-(-log(1-dble(10)**(dble(-x))))**(-xi))
            else
                t = aa - bb/xi*(1-10.**(x*xi))
            end if
        end if
        gevcovreturnlevel = t
        end
*  #] gevcovreturnlevel:
*  #[ gevcovreturnyear:
        real function gevcovreturnyear(a,b,xi,alpha,beta,xyear,cov)
!
!       compute the return time of the value xyear with the fitted values
!
        implicit none
        real a,b,xi,alpha,beta,xyear,cov
        real x,y,z,tx,arg,aa,bb

        x = xyear
        call getabfromcov(a,b,alpha,beta,cov,aa,bb)
        z = (1 + xi*(x-aa)/bb)
        if ( z.lt.0 ) then
            y = 1e20
        else if ( abs(xi).gt.1e-3 ) then
            y = -z**(-1/xi)
        else
            if ( xi.eq.0 ) then
                arg = -(x-aa)/bb
            else
                arg = -(x-aa)/bb + xi/2*((x-aa)/bb)**2
            end if
            if ( arg.gt.log(3e33) ) then
                y = -1e20
            else
                y = -exp(arg)
            end if
        end if
        if ( y.gt.1e19 ) then
            tx = 1e20 ! infinity, not undefined!
        else if ( y.gt.log(3e33) ) then
            tx = 0
        else if ( abs(y).gt.1e-3 ) then
            tx = 1/(1 - exp(y))
        else if ( abs(y).gt.1e-19 ) then
            tx = -1/(y + 0.5*y**2)
        else
            tx = 1e20
        end if
        if ( .false. .and. tx.gt.1e20 ) then
            write(0,*) 'gevcovreturnyear: tx > 1e20: ',tx
            write(0,*) 'a,b,xi,alpha,xyear = ',a,b,alpha,xi,xyear
        endif
        gevcovreturnyear = tx
        end
*  #] gevcovreturnyear: