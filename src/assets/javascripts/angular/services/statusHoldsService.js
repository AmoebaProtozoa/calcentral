'use strict';

var _ = require('lodash');

angular.module('calcentral.services').service('statusHoldsService', function() {

  var cnpStatusIcon = function(registration) {
    var positiveIndicators = _.get(registration, 'positiveIndicators');
    var indicatorTypes = [];
    _.forEach(positiveIndicators, function(indicator) {
      var indicatorType = _.get(indicator, 'type.code');
      indicatorTypes.push(indicatorType);
    });
    var hasR99 = _.includes(indicatorTypes, '+R99');
    var hasROP = _.includes(indicatorTypes, '+ROP');
    var pastFinancialDisbursement = _.get(registration, 'termFlags.pastFinancialDisbursement');

    if (hasR99) {
      return 'fa-check-circle cc-icon-green';
    } else if (!hasR99 && hasROP) {
      return 'fa-exclamation-triangle cc-icon-gold';
    } else if (!hasR99 && !hasROP) {
      return pastFinancialDisbursement ? 'fa-exclamation-circle cc-icon-red' : 'fa-exclamation-triangle cc-icon-gold';
    }
  };

  var regStatusIcon = function(regStatusSummary) {
    var icon = '';
    if (regStatusSummary === 'Officially Registered' || regStatusSummary === 'You have access to campus services.') {
      icon = 'fa-check-circle cc-icon-green';
    } else if (regStatusSummary === 'Not Officially Registered' || regStatusSummary === 'Not Enrolled') {
      icon = 'fa-exclamation-circle cc-icon-red';
    } else {
      icon = 'fa-exclamation-triangle cc-icon-gold';
    }
    return icon;
  };

  return {
    cnpStatusIcon: cnpStatusIcon,
    regStatusIcon: regStatusIcon
  };
});
