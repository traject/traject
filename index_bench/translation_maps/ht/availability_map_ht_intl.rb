require 'ht_traject/ht_constants'


mm = MatchMap.new
mm['ic'] = HathiTrust::Constants::SO
mm['umall'] = HathiTrust::Constants::FT
mm['orph'] = HathiTrust::Constants::SO
mm['world'] = HathiTrust::Constants::FT       # matches world, ic-world, und-world
mm['nobody'] = HathiTrust::Constants::SO
mm['und'] = HathiTrust::Constants::SO
mm[/^opb?$/] = HathiTrust::Constants::FT
mm[/^cc.*/] = HathiTrust::Constants::FT
mm['pd'] = HathiTrust::Constants::FT
mm['pdus'] = HathiTrust::Constants::SO

mm
