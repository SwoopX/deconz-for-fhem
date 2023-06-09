package main;

use strict;
use warnings;
use FHEM::Meta;
use POSIX;
use JSON;
use Data::Dumper;
use HttpUtils;
use IO::Socket::INET;
use DateTime::Format::ISO8601;      # libdatetime-format-iso8601-perl
use Protocol::WebSocket::Client;    # libprotocol-websocket-perl

my $client;
my $globalhash;
my $connected;

my %bool = ( "true"  => 1, 
             "false" => 0,
             "open"  => 1, 
             "closed" => 0
           );

my %settableLightStates = ( "alert"             => ":none,select,lselect ", 
                            "bri"               => ":colorpicker,BRI,0,1,255 ", 
                            "colorloopspeed"    => ":slider,1,1,255 ",
                            "ct"                => " ",
                            "effect"            => ":none,colorloop ",
                            "hue"               => ":colorpicker,HUE,0,1,65535 ",
                            "pct"               => ":colorpicker,BRI,0,1,100 ",
                            "sat"               => ":slider,0,1,255 ",
                            "transitiontime"    => " ",
                            "xy"                => " ",
                            "open"              => ":open,closed ",
                            "lift"              => ":slider,0,1,100 ",
                            "tilt"              => ":slider,0,1,100 "
                          );

my %configItems = ( "controlsequence"           => ":true,false ",
                    "coolsetpoint"              => " ",
                    "delay"                     => " ",
                    "devicemode"                => ":singlerocker,singlepushbutton,dualrocker,dualpushbutton,undirected,leftright,compatibility,zigbee ",
                    "clickmode"                 => ":highspeed,multiclick,coupled,decoupled ",
                    "displayflipped"            => ":true,false ",
                    "duration"                  => " ",
                    "externalsensortemp"        => " ",
                    "externalwindowopen"        => ":true,false ",
                    "fanmode"                   => ":off,low,medium,high,on,auto,smart ",
                    "heatsetpoint"              => " ",
                    "hostflags"                 => " ",
                    "interfacemode"             => ":1,2,3,4,5,6,7,8 ",
                    "ledindication"             => ":true,false ",
                    "locked"                    => ":true,false ",
                    "mode"                      => ":off,auto,cool,heat,emergencyheating,precooling,fanonly,dry,sleep ",
                    "mountingmode"              => ":true,false ",
                    "offset"                    => ":slider,-25,1,25 ",
                    "pulseconfiguration"        => " ",
                    "preset"                    => " ",
                    "resetpresence"             => ":true,false ",
                    "schedule"                  => " ",
                    "schedule_on"               => ":true,false ",
                    "selftest"                  => ":true,false ",
                    "sensitivity"               => " ",
                    "setvalve"                  => " ",
                    "swingmode"                 => ":fullyclosed,fullyopen,quarteropen,halfopen,threequartersopen ",
                    "temperaturemeasurement"    => ":airsensor,floorsensor,floorprotection ",
                    "tholddark"                 => " ",
                    "tholdoffset"               => " ",
                    "triggerdistance"           => ":far,medium,near ",
                    "usertest"                  => ":true,false ",
                    "windowscoveringtype"       => " ",
                    "loadbalancing"                  => ":true,false ",
                    "radiatorcovered"                  => ":true,false ",
                    "windowopendetectionenabled"                  => ":true,false ",
                    "meanloadroom"                  => " ",
                    "adaptationrun"                  => ":none,calibrate,cancelled ",
                    "adaptationsetting"                  => ":night,now "
                  );
                  
my %dim_values = ( 0    => "dim06%",
                   1    => "dim12%",
                   2    => "dim18%",
                   3    => "dim25%",
                   4    => "dim31%",
                   5    => "dim37%",
                   6    => "dim43%",
                   7    => "dim50%",
                   8    => "dim56%",
                   9    => "dim62%",
                   10   => "dim68%",
                   11   => "dim75%",
                   12   => "dim81%",
                   13   => "dim87%",
                   14   => "dim93%"
                 );

sub deCONZ_Initialize($)
{
    my ($hash) = @_;

    $hash->{DefFn}                = "deCONZ_Define";
    $hash->{UndefFn}              = "deCONZ_Undef";
    $hash->{DeleteFn}             = "deCONZ_Delete";
    $hash->{SetFn}                = "deCONZ_Set";
    $hash->{GetFn}                = "deCONZ_Get";
    $hash->{AttrFn}               = "deCONZ_Attr";
    $hash->{ReadFn}               = "deCONZ_Read";
    $hash->{ReadyFn}              = "deCONZ_Ready";
    $hash->{NotifyFn}             = "deCONZ_Notify";
    $hash->{RenameFn}             = "deCONZ_Rename";
    $hash->{ShutdownFn}           = "deCONZ_Shutdown";
    $hash->{DelayedShutdownFn}    = "deCONZ_DelayedShutdown";
    $hash->{AttrList}             = "apikey autocreate:1,0 disable:1 subType IODev model color-icons delayedUpdate $readingFnAttributes";
    
    #if( !$modules{deCONZ}{LOADED} ) {
    #    my $ret = CommandReload( undef, "deCONZ" );
    #    Log3 undef, 1, $ret if( $ret );
    #}
}

sub deCONZ_Define($$)
{
    my ( $hash, $def ) = @_;
    my @requestParams;
    
    # define testing deCONZ gateway 127.0.0.1 8080
    my($a, $h) = parseParams($def);
    
    #Log3 $hash->{NAME}, 3, "[deCONZ]: " . $def;
    #Log3 $hash->{NAME}, 3, "[deCONZ]: [$a[2]] $a[3] $a[4] $a[5] $h->{IODev}";
    #Log3 $hash->{NAME}, 3, "[deCONZ]: $a $a->[1] $h->{IODev}";    
    
    $hash->{NAME} = $a->[0];
    $hash->{TYPE} = $a->[1];
    $hash->{resource} = $a->[2];
    
    #if(IsDevice($hash->{NAME}, $hash->{TYPE})) {
    #    Log3 $hash->{NAME}, 3, "[deCONZ]: Device with name \'$hash->{NAME}\' of type \'$hash->{NAME}\' does already exist";
    #    return;
    #}
    
    if($hash->{resource} eq "gateway") {
        $hash->{host} = $h->{host};
        $hash->{httpport} = $h->{httpport};
        
        my $reference = $hash->{resource} . "-" . $hash->{NAME};
        $modules{deCONZ}{defptr}{$reference} = $hash;
        
        Log3 $hash->{NAME}, 3, "[deCONZ]: $hash->{resource} $hash->{NAME} defined with host: $hash->{host} and httpport: $hash->{httpport}";
        readingsSingleUpdate($hash, "state", "defined", 1);
        
        @requestParams = ($hash, undef, undef, 0, "config");
    }
    elsif($hash->{resource} eq "sensors" || $hash->{resource} eq "lights" || $hash->{resource} eq "groups") {
        $hash->{id} = $h->{id};
        $hash->{IODev} = $defs{$h->{IODev}};
        
        my $reference = $hash->{resource} . $hash->{id};
        $modules{deCONZ}{defptr}{$reference} = $hash;
        
        Log3 $hash->{NAME}, 3, "[deCONZ]: $hash->{resource} $hash->{NAME} defined with id: $hash->{id} and IODev: $hash->{IODev}->{NAME}";
        $hash->{STATE} = "Initialized";
        
        my $path = $hash->{resource} . "/" . $hash->{id};
        @requestParams = ($hash, undef, undef, 0, $path);
    }
    else {
        return "[deCONZ] Define: inappropriate device definition. Usage:\n" .
               "Gateway: define <name> deCONZ gateway host=<host> httpport=<httpport>\n" .
               "Device: define <name> deCONZ [sensors|lights|groups] id=<resource_id> IODev=<gateway_name>";
    }
    
    RemoveInternalTimer($hash);
    if( $init_done ) {
        deCONZ_PerformHttpRequest(@requestParams);
    } else {
        InternalTimer(gettimeofday() + 10, "deCONZ_PerformHttpRequest", \@requestParams, 0);
    }
    
    return undef;
}

sub deCONZ_Undef($$)
{
    my ($hash,$arg) = @_;
    
    RemoveInternalTimer($hash);

    if($hash->{resource} eq "gateway") {
        if($hash->{STATE} eq "connected"){
            Log 1, "[deCONZ]: $hash->{NAME} - Disconnecting websocket...";
            $client->disconnect;
            deCONZ_closeWebsocket($hash);
        }
    }
    
    return undef;
}

sub deCONZ_Delete($$)
{
    my ( $hash, $name ) = @_;
    my $reference;
    
    if($hash->{resource} eq "gateway") {
        $reference = $hash->{resource} . "-" . $hash->{NAME};
    }
    else {
        $reference = $hash->{resource} . $hash->{id};
    }

    delete($modules{deCONZ}{defptr}{$reference});

    return undef;
}

sub deCONZ_Get($@)
{
    my ( $hash, $name, $cmd, @args ) = @_;
    my ($arg, @params) = @args;
    my $list = "resourcedata:noArg";
    my $type;
    my $path;
    my @requestParams = ($hash, undef, undef, 0, $path);
    
    #Log3 $hash->{NAME}, 3, "[deCONZ]: GET Resource - " . Dumper $hash;
    #Log3 $hash->{NAME}, 3, "[deCONZ]: GET Resource - " . Dumper $modules{deCONZ}{defptr};

    return "\"get $name\" needs to have at least one command" unless(defined($cmd));
    
    if($cmd eq "resourcedata") {
        if ($hash->{resource} eq "sensors" || $hash->{resource} eq "lights" || $hash->{resource} eq "groups") {
            $path = $hash->{resource} . "/" . $hash->{id};
            $type = "2";
        }
        elsif($hash->{resource} eq "gateway") {
            $path = "config";
        }
        else {
           return "Unknown command $cmd, choose one of $list";
        }
        
        @requestParams = ($hash, undef, undef, 0, $path);
    }
    elsif($hash->{resource} eq "gateway") {
        $list .= " allresourcetypes:lights,sensors,groups,rules,scenes,schedules,alarmsystems";
        
        if($cmd eq "allresourcetypes") {
            if(@args > 0) {
                $type = $args[0];
                $path = $args[0];
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        else {
            return "Unknown command $cmd, choose one of $list";
        }
        
        @requestParams = ($hash, undef, undef, 1, $path);
    }
    elsif($hash->{resource} eq "lights" && (exists($hash->{READINGS}->{hue}) || exists($hash->{READINGS}->{xy}))) {
        $list .= " rgb:noArg";
        
        if($cmd eq "rgb") {
            my $r = 0;
            my $g = 0;
            my $b = 0;

            my $colormode = ReadingsVal($hash->{NAME},"colormode","") if(exists($hash->{READINGS}->{colormode}));
            
            if($colormode eq "hs") {
                my $h;
                my $s;
                my $v;
                
                if(exists($hash->{READINGS}->{hue}) && exists($hash->{READINGS}->{sat})) {
                    $h = ReadingsVal($hash->{NAME},"hue","") / 65535.0;
                    $s = ReadingsVal($hash->{NAME},"sat","") / 255.0;
                    
                    if(exists($hash->{READINGS}->{bri})) {
                        $v = ReadingsVal($hash->{NAME},"bri","") / 255.0;
                        $v = 1 if($v == 0);
                    }
                    else {
                        $v = 1;
                    }
                    
                    ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);
                    
                    $r *= 255;
                    $g *= 255;
                    $b *= 255;
                }
            }
            elsif($colormode eq "xy") {
                my $xy;
                my $Y;
                
                if(exists($hash->{READINGS}->{xy})) {
                    $xy = ReadingsVal($hash->{NAME},"xy","");
                    $xy =~ m/(.+),(.+)/;   #m/(0\.\d+,0\.\d+)/
                    my ($x,$y) = ($1, $2);
                    
                    if(exists($hash->{READINGS}->{bri})) {
                        $Y = ReadingsVal($hash->{NAME},"bri","") / 255.0;
                        $Y = 1 if($Y == 0);
                    }
                    else {
                        $Y = 1;
                    }
                    
                    ($r,$g,$b) = deCONZ_xyyToRgb($x,$y,$Y);
                }
            }

            return sprintf("%02x%02x%02x", $r + 0.5, $g + 0.5, $b + 0.5);
        }
        else {
            return "Unknown command $cmd, choose one of $list";
        }
        
        #@requestParams = ($hash, undef, undef, 1, $path);
    }
    else
    {
        return "Unknown command $cmd, choose one of $list";
    }

    if($hash->{resource} eq "gateway" && defined($type)) {
        my $ret = "";
        $ret = deCONZ_PerformHttpRequest(@requestParams);
        #Log3 $hash->{NAME}, 3, "[deCONZ]: GET ACTION - " . Dumper $ret;
        #return deCONZ_PerformHttpRequest(@requestParams);
        my $res;
        
        foreach my $key ( sort {$a<=>$b} keys %{$ret} ) {
            #Log3 $hash->{NAME}, 3, "[deCONZ]: GET ACTION - $key";
            my $ref = $type . $key;
            my $fhem_name = $modules{deCONZ}{defptr}{$ref}->{NAME} if( defined($modules{deCONZ}{defptr}{$ref}) );
            
            $res .= sprintf( "%5s  %-32s %-26s %-40s", $key, $ret->{$key}{name}, $ret->{$key}{type}, $fhem_name ) . "\n";
            
        }
        
        $res = sprintf( "%5s  %-32s %-26s %-40s\n", "ID", "NAME", "TYPE", "FHEM" ) .$res if( $res );
        
        Log3 $hash->{NAME}, 3, "[deCONZ]: GET Resource - " . Dumper $res;
        return $res;
    }
    else {
        deCONZ_PerformHttpRequest(@requestParams);
    }
}

sub deCONZ_Set($$@)
{
    my ( $hash, $name, $cmd, @args ) = @_;
    my $method = "PUT";
    my $obj;
    my $path;
    
    if($hash->{resource} eq "lights" || $hash->{resource} eq "groups") {
        my $list = "rename deletelightwithreset:false,true ";
        
        foreach my $stateReading ( sort keys %{$hash->{READINGS}} ) {
            if($stateReading eq "ct") {                
                if(exists($hash->{ctmin}) && exists($hash->{ctmax})) {
                    $list .= $stateReading . ":colorpicker,CT," . $hash->{ctmin} . ",1," . $hash->{ctmax} . " ";
                    $list .= "ctUp:noArg ctDown:noArg ";
                }
                elsif($hash->{resource} eq "groups") {
                    $list .= $stateReading . ":colorpicker,CT,154,1,350 ";
                    $list .= "ctUp:noArg ctDown:noArg ";
                }
            }
            elsif($stateReading eq "bri") {
                $list .= $stateReading . $settableLightStates{$stateReading};
                $list .= "dimUp:noArg dimDown:noArg ";
            }
            elsif($stateReading eq "sat") {
                $list .= $stateReading . $settableLightStates{$stateReading};
                $list .= "satUp:noArg satDown:noArg ";
            }
            elsif($stateReading eq "hue") {
                $list .= $stateReading . $settableLightStates{$stateReading};
                $list .= "hueUp:noArg hueDown:noArg ";
                $list .= "rgb:colorpicker,RGB ";
            }
            elsif($stateReading eq "xy") {
                $list .= $stateReading . $settableLightStates{$stateReading};
                $list .= "rgb:colorpicker,RGB ";
            }
            else {
                $list .= $stateReading . $settableLightStates{$stateReading} if(exists($settableLightStates{$stateReading}));
            }
        }
        
        if($cmd eq "rename") {
            if(@args > 0) {
                $obj = { "name" => $args[0] };
                $path = $hash->{resource} . "/" . $hash->{id};
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "deletelightwithreset") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { "reset" => $value };
                $path = $hash->{resource} . "/" . $hash->{id};
                $method = "DELETE";
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        else {
            $path = $hash->{resource} . "/" . $hash->{id} . "/state";
            $path = $hash->{resource} . "/" . $hash->{id} . "/action" if($hash->{resource} eq "groups");
            
            if(defined($hash->{type}) && ($hash->{type} =~ m/^Window/)) {
                $list .= "stop:noArg ";
                
                if($cmd eq "open") {
                    if(@args > 0 && exists($bool{$args[0]})) {
                        my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                        $obj = { $cmd => $value };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "stop") {
                    $obj = { $cmd => JSON::true };
                }
                elsif($cmd eq "lift") {
                    if(@args > 0) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "tilt") {
                    if(@args > 0) {
                        $obj = { $cmd => int($args[0]) };
                    }
                }
                else {
                    return "Unknown command $cmd, choose one of $list";
                }
            }
            else {
                $list .= "on:noArg off:noArg toggle:noArg rgb:colorpicker,RGB";
            
                if($cmd eq "on") {
                    $obj = { $cmd => JSON::true };
                }
                elsif($cmd eq "off") {
                    $obj = { "on" => JSON::false };
                }
                elsif($cmd eq "toggle") {
                    $obj = { "on" => Value($name) eq "on" ? JSON::false : JSON::true };
                }
                elsif($cmd eq "alert") {
                    if(@args > 0 && $args[0] =~ m/^(none|select|lselect)$/) {
                        $obj = { $cmd => $args[0] };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "bri") {
                    if(@args > 0 && $args[0] >= 0 && $args[0] <= 255) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "colorloopspeed") {
                    if(@args > 0 && $args[0] >= 1 && $args[0] <= 255) {
                        $obj = { $cmd => $args[0] };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "ct") {
                    if(@args > 0 && $args[0] >= $hash->{ctmin} && $args[0] <= $hash->{ctmax}) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    elsif(@args > 0 && $hash->{resource} eq "groups" && $args[0] >= 154 && $args[0] <= 350) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "effect") {
                    if(@args > 0 && $args[0] =~ m/^(none|colorloop)$/) {
                        $obj = { $cmd => $args[0] };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "hue") {
                    if(@args > 0 && $args[0] >= 0 && $args[0] <= 65535) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "sat") {
                    if(@args > 0 && $args[0] >= 0 && $args[0] <= 255) {
                        $obj = { $cmd => int($args[0]) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "xy") {
                    if(@args > 0 && $args[0] =~ m/(0\.\d+,0\.\d+)/) {
                        my ($x,$y) = ($1, $2);
                        $obj = { $cmd => [0 + $x, 0 + $y] };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "pct") {
                    if(@args > 0 && $args[0] >= 0 && $args[0] <= 100) {
                        $obj = { "bri" => int(($args[0] * 255) / 100) };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                elsif($cmd eq "dimUp" || $cmd eq "satUp" || $cmd eq "ctUp" || $cmd eq "hueUp" || 
                      $cmd eq "dimDown" || $cmd eq "satDown" || $cmd eq "ctDown" || $cmd eq "hueDown") {
                    my $increase;
                    
                    if(index($cmd, "Up") != -1) {
                        $cmd =~ s/Up//;
                        $increase = 1;
                    }
                    elsif(index($cmd, "Down") != -1) {
                        $cmd =~ s/Down//;
                        $increase = 0;
                    }
                    else {
                        return "Unknown command $cmd, choose one of $list";
                    }
                    
                    $cmd = "bri" if($cmd eq "dim");

                    if(exists($hash->{READINGS}->{$cmd})) {
                        my $value = ReadingsVal($hash->{NAME},$cmd,"");
                        my $step = 0;
                        $step = 25 if($cmd eq "bri" || $cmd eq "sat");
                        $step = 6553 if($cmd eq "hue");
                        $step = 16 if($cmd eq "ct");
                        
                        if($increase) {
                            $value += $step;
                        }
                        else {
                            $value -= $step;
                        }
                        
                        $value = 255 if($value > 255 && $increase && ($cmd eq "bri" || $cmd eq "sat"));
                        $value = 0 if($value < 0 && !$increase && ($cmd eq "bri" || $cmd eq "sat"));
                        $value = 65535 if($value > 65535 && $increase && $cmd eq "hue");
                        $value = 0 if($value < 0 && !$increase && $cmd eq "hue");
                        
                        if($cmd eq "ct" && exists($hash->{ctmin}) && exists($hash->{ctmax})) {
                            $value = $hash->{ctmax} if($increase && $value > $hash->{ctmax});
                            $value = $hash->{ctmin} if(!$increase && $value < $hash->{ctmin});
                        }
                        
                        $obj = { $cmd => $value };
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                } 
                elsif($cmd eq "rgb") {
                    if(@args > 0) {
                        $args[0] =~ m/^(..)(..)(..)/;
                        my($r, $g, $b) = (hex($1) / 255.0, hex($2) / 255.0, hex($3) / 255.0);
                        my $colormode = ReadingsVal($hash->{NAME},"colormode","") if(exists($hash->{READINGS}->{colormode}));
                        
                        if($colormode eq "hs") {
                            my($h, $s, $v) = Color::rgb2hsv($r,$g,$b);
                            
                            $obj = { "on" => JSON::true };
                            $obj += { "hue" => int($h * 65535) };
                            $obj += { "sat" => int($s * 255) };
                            $obj += { "bri" => int($h * int($v * 255)) } if(exists($hash->{READINGS}->{bri}));
                        }
                        elsif($colormode eq "xy") {
                            # calculation from http://www.everyhue.com/vanilla/discussion/94/rgb-to-xy-or-hue-sat-values/p1

                            my $X =  1.076450 * $r - 0.237662 * $g + 0.161212 * $b;
                            my $Y =  0.410964 * $r + 0.554342 * $g + 0.034694 * $b;
                            my $Z = -0.010954 * $r - 0.013389 * $g + 1.024343 * $b;
                            #Log3 $name, 3, "rgb: ". $r . " " . $g ." ". $b;
                            #Log3 $name, 3, "XYZ: ". $X . " " . $Y ." ". $Y;

                            if( $X != 0 || $Y != 0 || $Z != 0 ) {
                                my $x = $X / ($X + $Y + $Z);
                                my $y = $Y / ($X + $Y + $Z);
                                #Log3 $name, 3, "xyY:". $x . " " . $y ." ". $Y;

                                $Y = 1 if($Y > 1);
                                $x = 0 if($x < 0);
                                $x = 1 if($x > 1);
                                $y = 0 if($y < 0);
                                $y = 1 if($y > 1);

                                my $bri = maxNum($r,$g,$b);
                                #my $bri  = $Y;
                                
                                $obj = { "on" => JSON::true };
                                $obj += { "xy" => [0 + $x, 0 + $y] };
                                $obj += { "bri" => int(254 * $bri) } if(exists($hash->{READINGS}->{bri}));
                            }
                        }
                    }
                    else {
                        return "Unknown argument value for $cmd, choose one of $list";
                    }
                }
                else {
                    return "Unknown command $cmd, choose one of $list";
                }
            }
        }

        my @requestParams = ($hash, $method, $obj, 0, $path);
        
        deCONZ_PerformHttpRequest(@requestParams);
    }
    elsif($hash->{resource} eq "sensors") {
        my $list = "rename deletelightwithreset:false,true ";
        $path = $hash->{resource} . "/" . $hash->{id} . "/config";
        
        foreach my $stateReading ( sort keys %{$hash->{READINGS}} ) {
            #Log3 $hash->{NAME}, 3, "[deCONZ]: AVAILABLE READING - $stateReading";
            
            if(exists($configItems{$stateReading})) {
                #Log3 $hash->{NAME}, 3, "[deCONZ]: Item is configurable - $stateReading";
                #Log3 $hash->{NAME}, 3, "[deCONZ]: Item is configurable - $configItems{$stateReading}";
                $list .= $stateReading . $configItems{$stateReading};
            }
        }
        
        if($cmd eq "rename") {
            if(@args > 0) {
                $obj = { "name" => $args[0] };
                $path = $hash->{resource} . "/" . $hash->{id};
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "deletelightwithreset") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { "reset" => $value };
                $path = $hash->{resource} . "/" . $hash->{id};
                $method = "DELETE";
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "controlsequence") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "coolsetpoint") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0] * 100) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "delay") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0]) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "devicemode") {
            if(@args > 0 && $args[0] =~ m/^(singlerocker|singlepushbutton|dualrocker|dualpushbutton|undirected|leftright|compatibility|zigbee|action|scene)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "resetpresence") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "selftest") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "loadbalancing") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "radiatorcovered") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "windowopendetectionenabled") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "meanloadroom") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0])};
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "adaptationrun") {
            if(@args > 0 && $args[0] =~ m/^(idle|calibrate|cancelled)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "adaptationsetting") {
            if(@args > 0 && $args[0] =~ m/^(night|now)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "clickmode") {
            if(@args > 0 && $args[0] =~ m/^(highspeed|multiclick|coupled|decoupled|rocker|momentary)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "displayflipped") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "duration") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0]) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "externalsensortemp") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0] * 100)};
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "externalwindowopen") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "fanmode") {
            if(@args > 0 && $args[0] =~ m/^(off|low|medium|high|on|auto|smart)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "heatsetpoint") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0] * 100) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "ledindication") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "locked") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "mode") {
            if(@args > 0 && $args[0] =~ m/^(off|auto|cool|heat|emergencyheating|precooling|fanonly|dry|sleep)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "mountingmode") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "schedule_on") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "sensitivity") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0]) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "swingmode") {
            if(@args > 0 && $args[0] =~ m/^(fullyclosed|fullyopen|quarteropen|halfopen|threequartersopen)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "temperaturemeasurement") {
            if(@args > 0 && $args[0] =~ m/^(airsensor|floorsensor|floorprotection)$/) {
                $obj = { $cmd => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "offset") {
            if(@args > 0) {
                $obj = { $cmd => int($args[0] * 100) };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "usertest") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { $cmd => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        else {
            return "Unknown command $cmd, choose one of $list";
        }

        my @requestParams = ($hash, $method, $obj, 0, $path);
        
        deCONZ_PerformHttpRequest(@requestParams);
        
    }
    elsif($hash->{resource} eq "gateway") {
        my $list = "rename permitjoin:0,60,120,180 otauactive:true,false unlock websocketnotifyall:true,false lightlastseeninterval pair:noArg migrateFromHUEModule ";
        $path = "config";
        
        if(exists($hash->{helper}->{apikeys})) {
            my $hash_count = keys %{$hash->{helper}->{apikeys}};
            my $i = 1;
            
            $list .= "deleteApiKey:";
            
            foreach my $apikey ( sort keys %{$hash->{helper}->{apikeys}} ) {                
                my $values = $hash->{helper}->{apikeys}->{$apikey};                
                my $name = $values->{"name"};
                $name =~ s/\s//;
                my $lastused = $values->{"last use date"};
                my $created = $values->{"create date"};
                
                $list .= $apikey . "#" . $name . "#Lastused:" . $lastused . "#Created:" . $created;
                
                if($i < $hash_count) {
                    $i++;
                    $list .= ",";
                } 
            }
            
            $list .= " ";
        }

        if($cmd eq "rename") {
            if(@args > 0) {
                $obj = { "name" => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "permitjoin") {
            if(@args > 0) {
                $obj = { "permitjoin" => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "otauactive") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { "displayflipped" => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "unlock") {
            if(@args > 0) {
                $obj = { "unlock" => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "websocketnotifyall") {
            if(@args > 0 && exists($bool{$args[0]})) {
                my $value = $bool{$args[0]} ? JSON::true : JSON::false;
                $obj = { "displayflipped" => $value };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "lightlastseeninterval") {
            if(@args > 0) {
                $obj = { "lightlastseeninterval" => $args[0] };
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "pair") {
            readingsSingleUpdate($hash, "state", "pairing", 1);
            deCONZ_pair($hash);
            return;
        }
        elsif($cmd eq "migrateFromHUEModule") {
            if(@args > 0) {
                return deCONZ_migrate($args[0]);
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        elsif($cmd eq "deleteApiKey") {
            if(@args > 0) {
                $method = "DELETE";
                $path .= "/whitelist/$args[0]";
                
            }
            else {
                return "Unknown argument value for $cmd, choose one of $list";
            }
        }
        else {
            return "Unknown command $cmd, choose one of $list";
        }

        my @requestParams = ($hash, $method, $obj, 0, $path);
                
        deCONZ_PerformHttpRequest(@requestParams);
    }
}

sub deCONZ_Attr($$$$)
{
    my ($cmd, $name, $attrName, $attrValue) = @_;
    my $previous = $attrValue;
    
    if($cmd eq "set") {
        if($previous ne $attrValue) {
            $attr{$name}{$attrName} = $attrValue;
            return $attrName ." set to ". $attrValue;
        }
    }
}

sub deCONZ_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    if($hash->{CD}->connected) {
        my $recv_data;
        my $bytes_read = sysread $hash->{CD}, $recv_data, 16384;
        
        if (!defined $bytes_read) {
            Log 1, "[deCONZ]: Error on TCP socket - No bytes read";
        }
        elsif ($bytes_read == 0) {
            Log 1, "[deCONZ]: TCP connection terminated. Trying to reconnect...";
            
            my @requestParams = ($hash, undef, undef, 0, "config");
            
            deCONZ_closeWebsocket($hash);
            RemoveInternalTimer($hash);
            InternalTimer(gettimeofday() + 60, "deCONZ_PerformHttpRequest", \@requestParams, 0);
            return;
        }
        
        if(!defined($client)) {
            Log 1, "[deCONZ]: No websocket handler available. Trying to reconnect...";
            
            my @requestParams = ($hash, undef, undef, 0, "config");
            
            deCONZ_closeWebsocket($hash);
            RemoveInternalTimer($hash);
            InternalTimer(gettimeofday() + 60, "deCONZ_PerformHttpRequest", \@requestParams, 0);
            return;
        }
        
        # Make the hash reference of the device who initiated the websocket connection available throughout the module.
        # In environments with only a single DE coordinator, this could be neglected but if multiple are defined, it should be ensured
        # that websocket notifications of devices will be considered in the context of the right coordinator.
        $globalhash = \$hash;
        
        # Process received websocket data
        $client->read($recv_data);
    }
}

sub deCONZ_Ready($)
{
    my ( $hash ) = @_;

    return undef;
}

sub deCONZ_Notify($$)
{
    my ($hash,$dev) = @_;
    my $name  = $hash->{NAME};
    my $type  = $hash->{TYPE};

    return if($dev->{NAME} ne "global");
    return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

    if( IsDisabled($name) > 0 ) {
        readingsSingleUpdate($hash, "state", "inactive", 1) if( ReadingsVal($name, "inactive", "") ne "disabled" );
        return undef;
    }

    #deCONZ_openWebsocket($hash);

    return undef;
}

sub deCONZ_Rename($$)
{
    my ($new_name, $old_name) = @_;
    
    foreach my $key (keys %defs) {
        my $hash = $defs{$key};
        
        next if( $hash->{TYPE} ne "deCONZ" );
        next if( $hash->{resource} ne "gateway" );
        next if( $hash->{NAME} ne $new_name );
        
        foreach my $key (keys %defs) {
            my $hash = $defs{$key};
            
            next if( $hash->{TYPE} ne "deCONZ" );
            next if( $hash->{resource} eq "gateway" );
            $hash->{IODev} = $new_name if( $hash->{IODev} ne $new_name );

        }

        if($hash->{host} eq $client->{url}->{host} && $hash->{websocketport} eq $client->{url}->{port}) {
            Log 1, "[deCONZ]: Websocket connected";
            readingsSingleUpdate($hash, "state", "connected", 1);
        }
    }

    return undef;
}

sub deCONZ_DelayedShutdown($)
{
    my ( $hash ) = @_;

    return undef;
}

sub deCONZ_Shutdown($)
{
    my ( $hash ) = @_;
    
    if($hash->{resource} eq "gateway") {
        if($hash->{STATE} eq "connected"){
            Log 1, "[deCONZ]: $hash->{NAME} - Disconnecting websocket...";
            $client->disconnect;
            deCONZ_closeWebsocket($hash);
        }
    }

    return undef;
}

sub deCONZ_openWebsocket($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{host};
    my $port = $hash->{websocketport};
    
    if($hash->{STATE} eq "connected") {
        return;
    }
    
    if(!defined($port) || !defined($host)) {
        Log 1, "[deCONZ]: Cannot access deCONZ via websocket, as either host or port is not available";
        return;
    }
    
    # Create TCP socket for deCONZ with host and port information provided by previous HTTP API call
    my $tcp_socket = IO::Socket::INET->new( PeerAddr => $host,
                                            PeerPort => $port,
                                            Proto => 'tcp',
                                            Blocking => 1
                                            );
    
    if($tcp_socket) {
        $hash->{CD}    = $tcp_socket;
        $hash->{FD}    = $tcp_socket->fileno();
        $hash->{PORT}  = $tcp_socket->sockport if( $tcp_socket->sockport );

        $selectlist{$name} = $hash;
    }
    
    # Create websocket protocol handler
    $client = Protocol::WebSocket::Client->new(url => "ws://$host:$port");
    
    $client->on(
            write => sub {
                    my $client = shift;
                    my ($buf) = @_;
                    syswrite $tcp_socket, $buf;
                    }
            );
    
    $client->on(
            connect => \&deCONZ_websocketConnected
            );
    
    $client->on(
            error => sub {
                    my $client = shift;
                    my ($buf) = @_;
                    Log 1, "[deCONZ]: Websocket error: $buf";
                    $tcp_socket->close;
                    return;
                    }
            );

    $client->on(
            read => \&deCONZ_readFromWebsocket
            );
    
    Log 1, "[deCONZ]: Connecting to websocket server ws://$host:$port...";
    $client->connect;
}

sub deCONZ_websocketConnected
{
    my $client = shift;
    
    foreach my $key (keys %defs) {
        my $hash = $defs{$key};
        
        next if( $hash->{TYPE} ne "deCONZ" );
        next if( $hash->{resource} ne "gateway" );

        if($hash->{host} eq $client->{url}->{host} && $hash->{websocketport} eq $client->{url}->{port}) {
            Log 1, "[deCONZ]: Websocket connected";
            readingsSingleUpdate($hash, "state", "connected", 1);
        }
    }
}

sub deCONZ_readFromWebsocket
{
    my $client = shift;
    my ($buf) = @_;
    
    my $obj = eval { JSON->new->utf8(0)->decode($buf) };

    if( $obj ) {
        deCONZ_updateFromWebsocket($$globalhash, $obj);
    } else {
        Log3 $$globalhash->{NAME}, 2, "[deCONZ]: $$globalhash->{NAME} - Unhandled websocket data $buf";
    }
}

sub deCONZ_closeWebsocket($)
{
    my ($hash) = @_;

    delete($hash->{buf});
    delete($hash->{websocket});
    close($hash->{CD}) if( defined($hash->{CD}) );
    delete($hash->{CD});
    delete($selectlist{$hash->{NAME}});
    delete($hash->{FD});
    delete($hash->{PORT});
    
    readingsSingleUpdate($hash, "state", "disconnected", 1);
}

sub deCONZ_updateFromWebsocket($$)
{
    my ($hash, $jsonData) = @_;
    my $name = $hash->{NAME};
    
    if( ref($jsonData) eq "HASH" ) {
        #Log3 $name, 5, "[deCONZ]: $name - Websocket data: " . Dumper $jsonData;
        
        my $type = $jsonData->{t};
        my $res = $jsonData->{r};
        my $event = $jsonData->{e};
        my $id = $jsonData->{id};
        my $uid = $jsonData->{uniqueid} if $jsonData->{uniqueid};
        
        #########################################
        #### TODO: implement further support ####
        #########################################
        
        if($res eq "alarmsystems" || $res eq "rules" || $res eq "scenes" || $res eq "schedules") {
            return;
        }
        
        my $reference = $res . $id;
        my $devHashToUpdate = $modules{deCONZ}{defptr}{$reference};
        
        #Log3 $name, 5, "[deCONZ]: $name - Module stuff: " . Dumper $modules{deCONZ}{defptr}{$reference};

        unless($devHashToUpdate) {
            my $autocreate = AttrVal($hash->{NAME}, "autocreate", "0");
            
            unless($autocreate) { return };
            
            if($res eq "sensors" || $res eq "lights" || $res eq "groups") {
                
                my $newResourceName = "deCONZ_" . $res . $id;

                Log3 $name, 4, "[deCONZ]: $name - Creating new resource '$newResourceName' of type '$res' and id '$id'";

                my $cmdret = CommandDefine(undef, "$newResourceName deCONZ $res id=$id IODev=$name");
                if($cmdret) {
                    Log3 $name, 1, "[deCONZ]: $name - Autocreate: An error occurred while creating resource id '$id': $cmdret";
                } else {
                    $cmdret = CommandAttr(undef, "$newResourceName room deCONZ");
                    $cmdret = CommandAttr(undef, "$newResourceName group deCONZ $res");
                }
            }

            return;
        }

        Log3 $name, 5, "[deCONZ]: $name - Reference: $reference";
        Log3 $name, 5, "[deCONZ]: $name - Websocket data: ". Dumper $jsonData;
        
        if($type eq "event" && $event eq "changed") {
        
            my %readings;
            
            if( ref($jsonData->{attr}) eq "HASH" ) {
                #Log3 $devHashToUpdate->{NAME}, 5, "[deCONZ]: $name - Attr update";
                #Log3 $name, 5, "[deCONZ]: $name - Attr update: " . ref($jsonData->{attr});
                if($jsonData->{attr}->{lastseen}) {
                    #$devHashToUpdate->{lastseen} = $jsonData->{attr}->{lastseen};
                    #Log3 $devHashToUpdate->{NAME}, 5, "[deCONZ]: $name - Attr $jsonData->{attr}->{lastseen}";
                }
                
                %readings = deCONZ_parseAttr($devHashToUpdate, $jsonData->{attr}, %readings);
            }
            
            if(defined($jsonData->{state}) && ref($jsonData->{state}) eq "HASH") {
                %readings = deCONZ_parseState($devHashToUpdate, $jsonData->{state}, %readings);
            }
            
            if(defined($jsonData->{action}) && ref($jsonData->{action}) eq "HASH") {
                %readings = deCONZ_parseState($devHashToUpdate, $jsonData->{action}, %readings);
            }
            
            if(defined($jsonData->{config}) && ref($jsonData->{config}) eq "HASH") {
                %readings = deCONZ_parseConfig($jsonData->{config}, %readings);
            }
            
            if( scalar keys %readings ) {
                readingsBeginUpdate($devHashToUpdate);

                my $i = 0;
                foreach my $key ( keys %readings ) {
                    if( defined($readings{$key}) ) {
                        readingsBulkUpdate($devHashToUpdate, $key, $readings{$key}, 1);
                        ++$i;
                    }
                }

                readingsEndUpdate($devHashToUpdate,1);
                delete $hash->{CHANGETIME};
            }            
        }
        elsif($type eq "event" && $event eq "added") {
        }
        elsif($type eq "event" && $event eq "deleted") {
        }
    }
}

sub deCONZ_ParseHttpResponse($;$$)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "")
    {
        Log 1, "[deCONZ]: Error for request to " . $param->{url};
        Log 1, "[deCONZ]: " . $err;
        $hash->{fullResponse} = $err;
        
        my @requestParams = ($hash, undef, undef, 0, $param->{path});
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 60, "deCONZ_PerformHttpRequest", \@requestParams, 0);    # Resend request on timeouts
    }

    elsif($data ne "")
    {
        Log 1, "[deCONZ]: " . $param->{code} . " - Url " . $param->{url} . " returned data ";
        Log3 $name, 5, "[deCONZ]: Resource type: " . $hash->{resource};
        Log3 $name, 5, "[deCONZ]: Response data: " . $data;
        
        $hash->{fullResponse} = $data;
        
        if($param->{code} == 404) {       # Rarely, deCONZ doesn't return any expected content. We want to retry in that case
            if($data =~ m/(This is not the page you are looking for)/) {
                Log 1, "[deCONZ]: This is not the page you are looking for";
                
                my @requestParams = ($hash, undef, undef, 0, $param->{path});
                RemoveInternalTimer($hash);
                InternalTimer(gettimeofday() + 60, "deCONZ_PerformHttpRequest", \@requestParams, 0);    # Resend request on timeouts
        }
        
            
        }
        
        my $json = eval { JSON->new->utf8(0)->decode($data) };
        my $resource = $hash->{resource};
        my %readings;
        
        if( ref($json) eq "HASH" )
        {
            if($resource eq "gateway")
            {    
                $hash->{apiversion} = $json->{apiversion};
                $hash->{fwversion} = $json->{fwversion};
                $hash->{swversion} = $json->{swversion};
                $hash->{bridgeid} = $json->{bridgeid};
                $hash->{devicename} = $json->{devicename};
                $hash->{modelid} = $json->{modelid};
                $hash->{name} = $json->{name};
                $hash->{websocketnotifyall} = $json->{websocketnotifyall}?"true":"false";
                $hash->{websocketport} = $json->{websocketport};
                $hash->{zigbeechannel} = $json->{zigbeechannel};
                
                if(defined($json->{whitelist}) && ref($json->{whitelist}) eq "HASH" ) {
                    $hash->{helper}->{apikeys} = $json->{whitelist};
                }
                
                deCONZ_openWebsocket($hash);
            }
            elsif($resource eq "sensors" || $resource eq "lights" || $resource eq "groups")
            {
                %readings = deCONZ_parseAttr($hash, $json, %readings);
                
                if(defined($json->{state}))
                {
                    %readings = deCONZ_parseState($hash, $json->{state}, %readings);
                }
                
                if(defined($json->{action}))
                {
                    %readings = deCONZ_parseState($hash, $json->{action}, %readings);
                }
                
                if(defined($json->{config}))
                {
                    %readings = deCONZ_parseConfig($json->{config}, %readings);
                }
                
                if( scalar keys %readings )
                {
                    readingsBeginUpdate($hash);

                    my $i = 0;
                    foreach my $key ( keys %readings )
                    {
                        if( defined($readings{$key}) )
                        {
                            readingsBulkUpdate($hash, $key, $readings{$key}, 1);
                            ++$i;
                        }
                    }

                    readingsEndUpdate($hash,1);
                    delete $hash->{CHANGETIME};
                }
            }
            else {
                return $json;
            }
            
            return $json;
            
        }
        elsif( ref($json) eq "ARRAY" )
        {
            Log3 $name, 5, "[deCONZ]: ParseHttpResponse ARRAY part: " . Dumper $json;
            Log3 $name, 5, "[deCONZ]: ParseHttpResponse ARRAY part: $param->{url}";
            #Log3 $name, 5, "[deCONZ]: Received response: $json->[0]->{success}->{username}";
            
            #######################################################################
            #######################################################################
            if($resource eq "gateway" && $param->{url} eq "http://$hash->{host}:$hash->{httpport}/api") {
            #######################################################################
            #######################################################################
                
                return $json->[0];
            }
            
            #foreach my $respitem (@{$json}) {
            #    if(my $success = $respitem->{success}) {
            #        next if( ref($success) ne "HASH" );
            #        
            #        foreach my $key (keys %{$success}) {
            #            #my @content = split( ': ', $key );
            #            my $msg = $success->{$key};
            #            Log3 $name, 3, $msg;
            #        }
            #    }
            #    elsif(my $error = $respitem->{error}) {
            #        next if( ref($error) ne "HASH" );
            #        
            #        foreach my $key (keys %{$error}) {
            #            #my @content = split( ': ', $key );
            #            my $msg = $error->{$key};
            #            Log3 $name, 3, $msg;
            #        }
            #    }
            #}
            
            my @requestParams = ($hash, undef, undef, 0, "config");
            deCONZ_PerformHttpRequest(@requestParams) if($hash->{resource} eq "gateway");
        }
    }
    elsif($data eq "") {
        Log3 $name, 3, "[deCONZ]: HTTP request appears to have been successful, but response is empty...";
    }
}

sub deCONZ_iso8601ToLocalTime
{
    my ($hash, $datetime_str) = @_;
    #Log3 $hash->{NAME}, 5, "[deCONZ]: ISO8601 time ".$datetime_str;
    my $dt = DateTime::Format::ISO8601->parse_datetime($datetime_str)->epoch;
    #Log3 $hash->{NAME}, 5, "[deCONZ]: ISO8601 epoch ".$dt;
    my $timestamp = FmtDateTime($dt);
    #Log3 $hash->{NAME}, 5, "[deCONZ]: Local time ".$timestamp;
    $hash->{lastannounced} = $timestamp;
}

sub deCONZ_parseState
{
    my ($hash, $state, %readings) = @_;

    $readings{state} = $state->{status} if( defined($state->{status}) );
    $readings{state} = $state->{flag}?"1":"0" if( defined($state->{flag}) );
    $readings{state} = $state->{open}?"open":"closed" if( defined($state->{open}) );
    $readings{state} = $state->{lightlevel} if( defined($state->{lightlevel}) );
    $readings{state} = $state->{buttonevent} if( defined($state->{buttonevent}) );
    $readings{state} = $state->{presence}?"motion":"nomotion" if( defined($state->{presence}) );
    $readings{state} = $state->{fire}?"fire":"nofire" if( defined($state->{fire}) );
    $readings{state} = $state->{carbonmonoxide}?"co2":"noco2" if( defined($state->{carbonmonoxide}) );
    $readings{state} = $state->{alarm}?"alarm":"noalarm" if( defined($state->{alarm}) );
    $readings{state} = $state->{vibration}?"vibration":"novibration" if( defined($state->{vibration}) );
    $readings{state} = $state->{water}?"water":"nowater" if( defined($state->{water}) );
    
    #if($hash->{type} eq "Window covering controller" || $hash->{type} eq "Window covering device") {
    if(defined($hash->{type}) && $hash->{type} =~ m/^Window/) {
        $readings{state} = $state->{open}?"open":"closed" if( defined($state->{open}) );
        $readings{pct} = $state->{lift} if( defined($state->{lift}) );
    }
    else {
        $readings{state} = $state->{on}?"on":"off" if( defined($state->{on}) );
    }
    
    if(defined($hash->{type}) && $hash->{type} =~ m/(light|dimm|level)/) {
        $readings{pct} = int($state->{bri} * 100 / 255) if( defined($state->{bri}) );
    }
    
    $readings{reachable} = $state->{reachable}?"true":"false" if( defined($state->{reachable}) );
    $readings{dark} = $state->{dark}?"1":"0" if( defined($state->{dark}) );
    $readings{humidity} = $state->{humidity} * 0.01 if( defined($state->{humidity}) );
    $readings{daylight} = $state->{daylight}?"1":"0" if( defined($state->{daylight}) );
    $readings{temperature} = $state->{temperature} * 0.01 if( defined($state->{temperature}) );
    $readings{pressure} = $state->{pressure} if( defined($state->{pressure}) );
    $readings{lightlevel} = $state->{lightlevel} if( defined($state->{lightlevel}) );
    $readings{lux} = $state->{lux} if( defined($state->{lux}) );
    $readings{power} = $state->{power} if( defined($state->{power}) );
    $readings{voltage} = $state->{voltage} if( defined($state->{voltage}) );
    $readings{current} = $state->{current} if( defined($state->{current}) );
    $readings{consumption} = $state->{consumption} if( defined($state->{consumption}) );
    $readings{tampered} = $state->{tampered}?"true":"false" if( defined($state->{tampered}) );
    $readings{batteryPercent} = $state->{battery} if( defined($state->{battery}) );
    $readings{batteryState} = $state->{lowbattery}?"low":"ok" if( defined($state->{lowbattery}) );
    $readings{airquality} = $state->{airquality} if( defined($state->{airquality}) );
    $readings{airqualityppb} = $state->{airqualityppb} if( defined($state->{airqualityppb}) );
    $readings{errorcode} = $state->{errorcode} if( defined($state->{errorcode}) );
    $readings{mountingmodeactive} = $state->{mountingmodeactive}?"true":"false" if( defined($state->{mountingmodeactive}) );
    $readings{windowopen} = $state->{windowopen} if( defined($state->{windowopen}) );
    $readings{tiltangle} = $state->{tiltangle} if( defined ($state->{tiltangle}) );
    $readings{orientation} = join(',', @{$state->{orientation}}) if( defined($state->{orientation}) && ref($state->{orientation}) eq "ARRAY" );
    $readings{vibrationstrength} = $state->{vibrationstrength} if( defined ($state->{vibrationstrength}) );
    $readings{valve} = $state->{valve} if( defined ($state->{valve}) );
    $readings{gesture} = $state->{gesture} if( defined($state->{gesture}) );
    $readings{eventduration} = $state->{eventduration} if( defined($state->{eventduration}) );
    $readings{angle} = $state->{angle} if( defined($state->{angle}) );
    $readings{x} = $state->{x} if( defined($state->{x}) );
    $readings{y} = $state->{y} if( defined($state->{y}) );
    $readings{fanmode} = $state->{fanmode} if( defined($state->{fanmode}) );
    $readings{floortemperature} = $state->{floortemperature} if( defined($state->{floortemperature}) );
    $readings{heating} = $state->{heating}?"true":"false" if( defined($state->{heating}) );
    $readings{alert} = $state->{alert} if( defined($state->{alert}) );
    $readings{bri} = $state->{bri} if( defined($state->{bri}) && defined($hash->{type}) && $hash->{type} =~ m/^(?!Window)/);
    $readings{colorloopspeed} = $state->{colorloopspeed} if( defined($state->{colorloopspeed}) );
    $readings{ct} = $state->{ct} if( defined($state->{ct}) );
    $readings{effect} = $state->{effect} if( defined($state->{effect}) );
    $readings{hue} = $state->{hue} if( defined($state->{hue}) );
    $readings{sat} = $state->{sat} if( defined($state->{sat}) );
    $readings{transitiontime} = $state->{transitiontime} if( defined($state->{transitiontime}) );
    $readings{xy} = $state->{xy}[0] . "," . $state->{xy}[1] if( defined($state->{xy}) );
    $readings{open} = $state->{open}?"true":"false" if( defined($state->{open}) );
    $readings{lift} = $state->{lift} if( defined($state->{lift}) );
    $readings{tilt} = $state->{tilt} if( defined($state->{tilt}) );
    $readings{colormode} = $state->{colormode} if( defined($state->{colormode}) );
    $readings{scene} = $state->{scene} if( defined($state->{scene}) );
    $readings{all_on} = $state->{all_on} if( defined($state->{all_on}) );
    $readings{any_on} = $state->{any_on} if( defined($state->{any_on}) );
    $readings{presenceevent} = $state->{presenceevent} if( defined ($state->{presenceevent}) );
    $readings{charging} = $state->{charging} if( defined ($state->{charging}) );

    $readings{adaptationstatus} = $state->{adaptationstatus} if( defined ($state->{adaptationstatus}) );
    $readings{loadestimateradiator} = $state->{loadestimateradiator} if( defined ($state->{loadestimateradiator}) );
    $readings{loadestimate} = $state->{loadestimate} if( defined ($state->{loadestimate}) );

    if(!defined($attr{$hash->{NAME}}{webCmd})) {
        if($hash->{resource} eq "lights" && defined($hash->{type}) && $hash->{type} =~ m/^(?!Window)/) {
            $attr{$hash->{NAME}}{webCmd} = 'rgb:rgb ff0000:rgb DEFF26:rgb 0000ff:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if(exists($hash->{READINGS}->{xy}) && exists($hash->{READINGS}->{ct}));
            $attr{$hash->{NAME}}{webCmd} = 'hue:rgb:rgb ff0000:rgb 98FF23:rgb 0000ff:toggle:on:off' if(exists($hash->{READINGS}->{hue}) && !exists($hash->{READINGS}->{ct}));
            $attr{$hash->{NAME}}{webCmd} = 'ct:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if(!exists($hash->{READINGS}->{xy}) && !exists($hash->{READINGS}->{hue}) && exists($hash->{READINGS}->{ct}));
            $attr{$hash->{NAME}}{webCmd} = 'pct:toggle:on:off' if(!exists($hash->{READINGS}->{xy}) && !exists($hash->{READINGS}->{hue}) && !exists($hash->{READINGS}->{ct}) && exists($hash->{READINGS}->{bri}));
            $attr{$hash->{NAME}}{webCmd} = 'toggle:on:off' if(!exists($hash->{READINGS}->{xy}) && !exists($hash->{READINGS}->{hue}) && !exists($hash->{READINGS}->{ct}) && !exists($hash->{READINGS}->{bri}));
        }
        elsif($hash->{resource} eq "lights" && defined($hash->{type}) && $hash->{type} =~ m/^Window/) {
            $attr{$hash->{NAME}}{webCmd} = 'up:stop:down:pct';
        }
        elsif($hash->{resource} eq "groups") {
            $attr{$hash->{NAME}}{webCmd} = 'on:off';
        }
    }

    return %readings;
}

sub deCONZ_parseConfig
{
    my ($config, %readings) = @_;
    
    $readings{batteryPercent} = $config->{battery} if( defined($config->{battery}) );
    $readings{tholddark} = $config->{tholddark} if( defined($config->{tholddark}) );
    $readings{tholdoffset} = $config->{tholdoffset} if( defined($config->{tholdoffset}) );
    $readings{reachable} = $config->{reachable}?"true":"false" if( defined($config->{reachable}) );
    $readings{temperature} = $config->{temperature} * 0.01 if( defined($config->{temperature}) );
    $readings{heatsetpoint} = sprintf("%.1f",$config->{heatsetpoint} * 0.01) if( defined ($config->{heatsetpoint}) );
    $readings{locked} = $config->{locked}?"true":"false" if( defined ($config->{locked}) );
    $readings{displayflipped} = $config->{displayflipped}?"true":"false" if( defined ($config->{displayflipped}) );
    $readings{mode} = $config->{mode} if( defined ($config->{mode}) );
    $readings{offset} = $config->{offset} if( defined ($config->{offset}) );
    $readings{delay} = $config->{delay} if( defined ($config->{delay}) );
    $readings{duration} = $config->{duration} if( defined ($config->{duration}) );
    $readings{group} = $config->{group} if( defined ($config->{group}) );
    $readings{groups} = $config->{groups} if( defined ($config->{groups}) );
    $readings{schedule} = $config->{schedule} if( defined ($config->{schedule}) );
    $readings{schedule_on} = $config->{schedule_on}?"true":"false" if( defined ($config->{schedule_on}) );
    $readings{coolsetpoint} = $config->{coolsetpoint} if( defined ($config->{coolsetpoint}) );
    $readings{mountingmode} = $config->{mountingmode}?"true":"false" if( defined ($config->{mountingmode}) );
    $readings{externalsensortemp} = $config->{externalsensortemp} if( defined ($config->{externalsensortemp}) );
    $readings{externalwindowopen} = $config->{externalwindowopen}?"true":"false" if( defined ($config->{externalwindowopen}) );
    $readings{fanmode} = $config->{fanmode} if( defined($config->{fanmode}) );
    $readings{preset} = $config->{preset} if( defined($config->{preset}) );
    $readings{swingmode} = $config->{swingmode} if( defined($config->{swingmode}) );
    $readings{setvalve} = $config->{setvalve} if( defined($config->{setvalve}) );
    $readings{temperaturemeasurement} = $config->{temperaturemeasurement} if( defined($config->{temperaturemeasurement}) );
    $readings{enrolled} = $config->{enrolled} if( defined($config->{enrolled}) );
    $readings{ledindication} = $config->{ledindication}?"true":"false" if( defined($config->{ledindication}) );
    $readings{sensitivity} = $config->{sensitivity} if( defined($config->{sensitivity}) );
    $readings{sensitivitymax} = $config->{sensitivitymax} if( defined($config->{sensitivitymax}) );
    $readings{usertest} = $config->{usertest}?"true":"false" if( defined($config->{usertest}) );
    $readings{interfacemode} = $config->{interfacemode} if( defined($config->{interfacemode}) );
    $readings{pulseconfiguration} = $config->{pulseconfiguration} if( defined($config->{pulseconfiguration}) );
    $readings{triggerdistance} = $config->{triggerdistance} if( defined($config->{triggerdistance}) );
    $readings{resetpresence} = $config->{resetpresence} if( defined($config->{resetpresence}) );
    $readings{clickmode} = $config->{clickmode} if( defined($config->{clickmode}) );
    $readings{devicemode} = $config->{devicemode} if( defined($config->{devicemode}) );
    $readings{selftest} = $config->{selftest} if( defined($config->{selftest}) );

    $readings{adaptationrun} = $config->{adaptationrun} if( defined($config->{adaptationrun}) );
    $readings{adaptationsetting} = $config->{adaptationsetting} if( defined($config->{adaptationsetting}) );
    $readings{loadbalancing} = $config->{loadbalancing}?"true":"false" if( defined($config->{loadbalancing}) );
    $readings{radiatorcovered} = $config->{radiatorcovered}?"true":"false" if( defined($config->{radiatorcovered}) );
    $readings{windowopendetectionenabled} = $config->{windowopendetectionenabled}?"true":"false" if( defined($config->{windowopendetectionenabled}) );
    $readings{loadroommean} = $config->{loadroommean} if( defined($config->{loadroommean}) );
    $readings{meanloadroom} = $config->{meanloadroom} if( defined($config->{meanloadroom}) );

    return %readings;
}

sub deCONZ_parseAttr
{
    my ($hash, $attr, %readings) = @_;
    
    $hash->{manufacturername} = $attr->{manufacturername} if( defined ($attr->{manufacturername}) );
    $hash->{modelid} = $attr->{modelid} if( defined ($attr->{modelid}) );
    $hash->{name} = $attr->{name} if( defined ($attr->{name}) );
    $readings{lastseen} = "" if( defined ($attr->{lastseen}) );
    $hash->{swversion} = $attr->{swversion} if( defined ($attr->{swversion}) );
    $hash->{type} = $attr->{type} if( defined ($attr->{type}) );
    $hash->{uniqueid} = $attr->{uniqueid} if( defined ($attr->{uniqueid}) );
    $hash->{ctmin} = $attr->{ctmin} if( defined($attr->{ctmin}) );
    $hash->{ctmax} = $attr->{ctmax} if( defined($attr->{ctmax}) );
    $hash->{colorcapabilities} = $attr->{colorcapabilities} if( defined($attr->{colorcapabilities}) );
    
    
    $hash->{devicemembership} = join(", ", @{$attr->{devicemembership}}) if( defined($attr->{devicemembership}) );
    $hash->{lights} = join(", ", @{$attr->{lights}}) if( defined($attr->{lights}) );
    $hash->{scenes} = $attr->{scenes} if( defined($attr->{scenes}) );
    
    deCONZ_iso8601ToLocalTime($hash, $attr->{lastannounced}) if( defined($attr->{lastannounced}) );
    
    return %readings;
}

sub deCONZ_pair
{
    my ($hash) = @_;
    my $obj = { "devicetype" => "FHEM" };
    
    if(ReadingsVal($hash->{NAME}, "state", "") ne "pairing" || AttrVal($hash->{NAME}, "apikey", "") ne "") {
        Log3 $hash->{NAME}, 3, "[deCONZ]: API key already defined or not ready to pair " . AttrVal($hash->{NAME}, "apikey", "");
        return;
    }

    my $method = "POST";
    my @requestParams = ($hash, $method, $obj, 1, "api");
    
    my $ret = deCONZ_PerformHttpRequest(@requestParams);
    
    Log3 $hash->{NAME}, 5, "[deCONZ]: deCONZ_pair " . Dumper $ret;
    
    if($ret->{success}) {
        $attr{$hash->{NAME}}{"apikey"} = $ret->{success}->{username};
        
        @requestParams = ($hash, undef, undef, 1, "config");
        
        deCONZ_PerformHttpRequest(@requestParams);
    }
    else {
        Log3 $hash->{NAME}, 3, "[deCONZ]: deCONZ_pair Error while pairing...";
    }
}

sub deCONZ_PerformHttpRequest
{
    my ( $hash, $method, $obj, $blocking, $path ) = @_;
    my $json;
    my $baseUrl;
    my $apikey;
    my $url;
    
    if(ref($hash) ne "HASH") {
        $method = $hash->[1];
        $obj = $hash->[2];
        $blocking = $hash->[3];
        $path = $hash->[4];
        $hash = $hash->[0];
    }
    
    my $name = $hash->{NAME};
    
    $method = "GET" unless(defined($method));
    
    Log3 $name, 5, "[deCONZ]: $name - PerformHttpRequest hash: " . Dumper $hash;
    
    if($hash->{resource} ne "gateway") {
        if($hash->{IODev} && $hash->{IODev}->{STATE} ne "connected") {
            Log3 $name, 5, "[deCONZ]: $name - Do not send HTTP request as GW is not connected";
            
            # Send HTTP requests to devices again after gateway is connected
            my @requestParams = ($hash, undef, undef, 0, $path);
            RemoveInternalTimer($hash);
            InternalTimer(gettimeofday() + 60, "deCONZ_PerformHttpRequest", \@requestParams, 0);
            
            return;
        }
        
        my $gw = $hash->{IODev};
        $name = $gw->{NAME};
        $baseUrl = "http://$gw->{host}:$gw->{httpport}";
        $apikey = AttrVal($gw->{NAME}, "apikey", "");
    }
    else {
        $baseUrl = "http://$hash->{host}:$hash->{httpport}";
        $apikey = AttrVal($hash->{NAME}, "apikey", "");
    }

    if($apikey eq "") {      # Don't send HTTP requests without an API key...
        if(defined($method) && $method eq "POST" && $path =~ m/^api$/) {     # ...except for when requesting to obtain an API key
            $url = $baseUrl . "/" . $path;
            Log 1, "[deCONZ]: Requesting API key";
        }
        else {
            Log 1, "[deCONZ]: No API key available, not sending any request";
            return;
        }
    }
    elsif($path =~ m/$apikey/) {        # When a request is re-send, do not add API key again
        $url = $baseUrl . $path;
    }
    else {
        $url = $baseUrl . "/api/" . $apikey . "/" . $path;
    }
    
    if( defined( $obj ) ) {
        $json = encode_json( $obj );
    }
    
    unless($blocking) {
        Log 1, "[deCONZ]: $name - Sending NON-blocking request...";
        Log 1, "[deCONZ]: $name - $method $url";
        
        my $param = {
                url        => $url,
                timeout    => 5,
                hash       => $hash,
                method     => $method,
                data       => $json,
                #header     => "User-Agent: FHEM\r\nAccept: application/json",
                header     => "Content-Type: application/json",
                callback   => \&deCONZ_ParseHttpResponse
                };

        HttpUtils_NonblockingGet($param);
    }
    else {
        Log 1, "[deCONZ]: $name - Sending blocking request...";
        Log 1, "[deCONZ]: $name - $method $url";
        
        my $param = {
                url         => $url,
                timeout     => 5,
                hash        => $hash,
                method      => $method,
                data        => $json,
                header      => "Content-Type: application/json"
                };
                
        my( $err,$data ) = HttpUtils_BlockingGet( $param );
        
        return deCONZ_ParseHttpResponse( $param, $err, $data );
    }
}

sub deCONZ_devStateIcon
{
}

sub deCONZ_migrate
{
    my ($gateway) = @_;
    my $valid = 0;
    my $huebridge;
    my @stateitems = ( "state", "on", "reachable", "url", "lat", "long", "sunriseoffset", "sunsetoffset", "tholddark", "sensitivity",
                       "battery", "batteryPercent", "temperature", "sensitivitymax", "heatsetpoint", "locked", "displayflipped", "mode",
                       "offset", "delay", "duration", "group", "schedule_on", "coolsetpoint", "mountingmode", "status", "flag", "open",
                       "lightlevel", "buttonevent", "presence", "fire", "dark", "humidity", "daylight", "pressure", "lux", "power", "voltage",
                       "current", "consumption", "water", "tampered", "batteryState", "tiltangle", "vibration", "orientation",
                       "vibrationstrength", "valve", "carbonmonoxide", "gesture", "alert", "effect", "lastseen", "rgb", "pct", "onoff", "scene",
                       "stream_active", "colormode"
                     );
    
    foreach my $key (keys %defs) {
        my $hash = $defs{$key};
        
        #next if( $hash->{TYPE} ne "deCONZ" );
        #next if( $hash->{resource} ne "gateway" );
        
        if($hash->{TYPE} eq "deCONZ" && $hash->{resource} eq "gateway" && $hash->{NAME} eq $gateway) {
            $valid = 1;
            $gateway = $hash;
        }
        
        if($hash->{TYPE} eq "HUEBridge") {
            $huebridge = $hash;
        }
    }
    
    # Swap device positions so that deCONZ coordinator is defined and available as IODev for migrated HueDevices
    if(defined($huebridge) && $valid) {
        my $deconzposition = $gateway->{NR};
        $gateway->{NR} = $huebridge->{NR};
        $huebridge->{NR} = $deconzposition;
    }
    
    if($valid) {
        foreach my $key (keys %defs) {
            my $hash = $defs{$key};
            
            next if( $hash->{TYPE} ne "HUEDevice" );

            my @item = split(/ /, $hash->{DEF});

            #Log 1, "AAAAA " . $item[0] . ", "  . $item[1] . ", "  . $item[2] . ", "  . $item[3] . ", " . scalar @item;
            
            if($item[0] eq "sensor" || $item[0] eq "group") {
                my $resource = $item[0];
                my $id = $item[1];
                my @iodevitems = split(/=/, $item[3]);
                my $iodev = $iodevitems[1];
                
                Log 1, "Old definition: " . $resource . ", "  . $id . ", "  . $iodev;
                
                $resource .= "s";
                
                my $reference = $resource . $id;
                $modules{deCONZ}{defptr}{$reference} = $hash;
                
                my $def = $resource . " id=" . $id . " IODev=" . $gateway->{NAME};
                
                #Log 1, "New definition: " . $resource . " id=" . $id . " IODev=" . $gateway->{NAME};

                my $name = $hash->{NAME};
                CommandDeleteAttr(undef, "$name IODev");
                $hash->{DEF} = $def;
                $hash->{id} = $id;
                $hash->{resource} = $resource;
                $hash->{TYPE} = "deCONZ";
                delete($hash->{helper});
                delete($hash->{IODev});
                $hash->{IODev} = $gateway;
            }
            elsif(scalar @item == 3) {
                my $id = $item[0];
                my @iodevitems = split(/=/, $item[2]);
                my $iodev = $iodevitems[1];
                
                #Log 1, "Old definition: " . "light" . ", "  . $id . ", "  . $iodev;
                
                my $resource = "lights";
                
                my $reference = $resource . $id;
                $modules{deCONZ}{defptr}{$reference} = $hash;
                
                my $def = $resource . " id=" . $id . " IODev=" . $gateway->{NAME};
                
                #Log 1, "New definition: " . $resource . " id=" . $id . " IODev=" . $gateway->{NAME};
                
                my $name = $hash->{NAME};
                CommandDeleteAttr(undef, "$name IODev");
                $hash->{DEF} = $def;
                $hash->{id} = $id;
                $hash->{resource} = $resource;
                $hash->{TYPE} = "deCONZ";
                delete($hash->{helper});
                delete($hash->{IODev});
                $hash->{IODev} = $gateway;
            }
            
            my $icon = AttrVal($hash->{NAME}, "devStateIcon", "");
                
            Log 1, "Old definition: " . $hash->{NAME} . " - " . $icon;
            $icon =~ s/HUEDevice/deCONZ/;
            Log 1, "New definition: " . $hash->{NAME} . " - " . $icon;
            
            if($icon ne "") {
                CommandDeleteAttr(undef, "$hash->{NAME} devStateIcon");
                CommandAttr(undef, "$hash->{NAME} devStateIcon $icon");
            }
            
            # Delete previous readings. The new ones will be created when FHEM is started or resourcedata is read
            foreach my $key (@stateitems) {
                if(exists($hash->{READINGS}->{$key})) {
                    #Log 1, "Reading exists: " . $key ;
                    readingsDelete($hash, $key);
                }
            }
        }
        
        return "Migration complete";
    }
    else {
        return "No suitable deCONZ gateway defined or found";
    }
}

sub deCONZ_xyyToRgb($$$)
{
    # calculation from http://www.brucelindbloom.com/index.html
    my ($x,$y,$Y) = @_;
    #Log 3, "xyY:". $x . " " . $y ." ". $Y;

    my $r = 0;
    my $g = 0;
    my $b = 0;

    if($y > 0) {
        my $X = $x * $Y / $y;
        my $Z = (1 - $x - $y) * $Y / $y;

        if($X > 1 || $Y > 1 || $Z > 1) {
            my $f = maxNum($X,$Y,$Z);
            $X /= $f;
            $Y /= $f;
            $Z /= $f;
        }
        #Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

        $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
        $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
        $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

        if($r > 1 || $g > 1 || $b > 1) {
            my $f = maxNum($r,$g,$b);
            $r /= $f;
            $g /= $f;
            $b /= $f;
        }
        #Log 3, "rgb: ". $r . " " . $g ." ". $b;

        $r *= 255;
        $g *= 255;
        $b *= 255;
    }

    return($r, $g, $b);
}

1;

