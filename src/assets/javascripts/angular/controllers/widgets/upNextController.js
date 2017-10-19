'use strict';

var angular = require('angular');
var _ = require('lodash');

/**
 * My Up Next controller
 */
angular.module('calcentral.controllers').controller('UpNextController', function(apiService, upNextFactory, $scope) {
  /**
   * Make sure that we're not showing wrong date information to the user.
   * This will make sure that the date that is shown in the UI is the
   * same as the last modified date of the feed.
   * @param {Integer} epoch Last modified date epoch
   */
  var setLastModifiedDate = function(epoch) {
    $scope.lastModifiedDate = new Date(epoch * 1000);
  };

  var getUpNext = function(options) {
    upNextFactory.getUpNext(options).then(
      function successCallback(response) {
        if (!_.get(response, 'data.items')) {
          return;
        }
        angular.extend($scope, response.data);
        setLastModifiedDate(response.data.lastModified.timestamp.epoch);
      }
    );
  };

  getUpNext();
});
