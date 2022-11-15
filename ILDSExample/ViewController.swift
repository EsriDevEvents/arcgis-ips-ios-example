//
// COPYRIGHT 2022 ESRI
//
// TRADE SECRETS: ESRI PROPRIETARY AND CONFIDENTIAL
// Unpublished material - all rights reserved under the
// Copyright Laws of the United States and applicable international
// laws, treaties, and conventions.
//
// For additional information, contact:
// Environmental Systems Research Institute, Inc.
// Attn: Contracts and Legal Services Department
// 380 New York Street
// Redlands, California, 92373
// USA
//
// email: contracts@esri.com
//

import UIKit
import ArcGIS

class ViewController: UIViewController {
    @IBOutlet weak var mapView: AGSMapView!
    
    private let startStopButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let spinnerBoxView = UIView()
    
    private let portal = AGSPortal(url: URL(string: "https://viennardc.maps.arcgis.com")!, loginRequired: true)
    private let credential = AGSCredential(user: "SurveyAppUser1", password: "pwd.SurveyAppUser1")
    private let mapID = "598c664f9f594f45a4939988d03ff932"
    
    // Provides an indoor or outdoor position based on device sensor data (radio, GPS, motion sensors).
    private var ilds: AGSIndoorsLocationDataSource?
    private let locationManager = CLLocationManager()
    private var setupResultCompletion: (Result<Void, Error>) -> Void = { _ in }
    private var stopping = false
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupResultCompletion = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case let .failure(error):
                self.showError(error: error)
            case .success():
                self.setupLocationDisplay()
            }
        }
        
        setupStartStopButton()
        setupSpinnerBox()
        hideSpinner()
        
        locationManager.delegate = self
    }

    private func setupLocationDisplay() {
        guard let ilds = ilds else { return }

        mapView.locationDisplay.autoPanMode = AGSLocationDisplayAutoPanMode.compassNavigation
        mapView.locationDisplay.dataSource = ilds

        ilds.locationChangeHandlerDelegate = self

        startLocationDisplay()
    }

    private func startLocationDisplay() {
        // Asynchronously start of the location display, which will in-turn start IndoorsLocationDataSource to start receiving IPS updates.
        mapView.locationDisplay.start { [weak self] (error) in
            guard let self = self, let error = error else { return }
            self.showError(error: error)
        }
    }
    
    private func connectToPortal() {
        portal.credential = credential
        portal.load { [weak self] (error) in
            guard let weakSelf = self else { return }
            
            let portalItem = AGSPortalItem(portal: weakSelf.portal, itemID: weakSelf.mapID)
            weakSelf.setupMap(map: AGSMap(item: portalItem))
        }
    }
    
    private func setupMap(map: AGSMap) {
        mapView.map = map
        mapView.map?.load(completion: { [weak self] (error) in
            guard let self = self else { return }

            if let error = error {
                self.showError(error: error)
            } else {
                guard let map = self.mapView.map else { return }

                self.loadMapTables(map: map)
            }
        })
    }
    
    private func loadMapTables(map: AGSMap) {
        let tables = self.mapView.map?.tables as! [AGSFeatureTable]

        loadTables(tables: tables) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(_):
                self.showError(error: SetupError.failedToLoadFeatureTables)
            case .success():
                self.setupIndoorsLocationDataSource(tables: tables, completion: self.setupResultCompletion)
            }
        }
    }
    
    private func setupIndoorsLocationDataSource(tables: [AGSFeatureTable], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let positioningTable = tables.first(where: {$0.tableName == "IPS_Positioning"}) else {
            completion(.failure(SetupError.positioningTableNotFound))
            return
        }

        // Setting up IndoorsLocationDataSource with positioning, pathways tables
        ilds = AGSIndoorsLocationDataSource(positioningTable: positioningTable, pathwaysTable: getPathwaysTable())
        
        completion(.success(()))
    }
    
    private func getPathwaysTable() -> AGSArcGISFeatureTable? {
        return (mapView.map?.operationalLayers as! [AGSFeatureLayer]).first(where: {$0.name == "Pathways"})?.featureTable as? AGSArcGISFeatureTable
    }
    
    private func loadTables(tables: [AGSFeatureTable], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let table = tables.last else {
            completion(.success(()))
            return
        }

        table.load { [weak self] error in
            if let error = error {
                completion(.failure(error))
                return
            }

            self?.loadTables(tables: tables.dropLast(), completion: completion)
        }
    }
    
    private enum SetupError: LocalizedError {
        case failedToLoadFeatureTables
        case positioningTableNotFound
        
        var errorDescription: String? {
            switch self {
            case .failedToLoadFeatureTables:
                return NSLocalizedString("Failed to load feature tables", comment: "")
            case .positioningTableNotFound:
                return NSLocalizedString("Positioning table not found", comment: "")
            }
        }
    }
    
    private func showError(error: Error) {
        let alert = UIAlertController(
            title: "",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        present(alert, animated: true, completion: nil)
    }
    
    @objc
    func startStopButtonTapped() {
        if startStopButton.titleLabel?.text == "Start ILDS" {
            let tables = self.mapView.map?.tables as! [AGSFeatureTable]
            setupIndoorsLocationDataSource(tables: tables, completion: setupResultCompletion)
            hideStartStopButton()
        } else {
            stopping = true
            ilds = nil
            mapView.locationDisplay.stop()
        }
    }
    
    private func setupStartStopButton() {
        startStopButton.addTarget(self, action: #selector(startStopButtonTapped), for: .touchUpInside)
        startStopButton.setTitle("Stop ILDS", for: .normal)
        startStopButton.setTitleColor(.white, for: .normal)
        startStopButton.layer.cornerRadius = 2
        startStopButton.layer.masksToBounds = true
        startStopButton.backgroundColor = .gray
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(startStopButton)

        NSLayoutConstraint.activate([
            startStopButton.heightAnchor.constraint(equalToConstant: 45),
            startStopButton.leftAnchor.constraint(equalTo: mapView.leftAnchor, constant: 140),
            startStopButton.rightAnchor.constraint(equalTo: mapView.rightAnchor, constant:  -140),
            startStopButton.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -30)
        ])
    }
    
    private func showStartStopButton() {
        startStopButton.isEnabled = true
        startStopButton.isHidden = false
    }

    private func hideStartStopButton() {
        startStopButton.isHidden = true
        startStopButton.isEnabled = false
    }
    
    private func setupSpinnerBox() {
        spinnerBoxView.translatesAutoresizingMaskIntoConstraints = false
        spinnerBoxView.backgroundColor = .white
        spinnerBoxView.alpha = 0.97
        spinnerBoxView.layer.cornerRadius = 10
        spinnerBoxView.clipsToBounds = true

        view.addSubview(spinnerBoxView)

        NSLayoutConstraint.activate([
            spinnerBoxView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinnerBoxView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinnerBoxView.widthAnchor.constraint(equalToConstant: 100),
            spinnerBoxView.heightAnchor.constraint(equalToConstant: 100)
        ])

        let label = UILabel()
        label.text = "Starting ILDS..."
        label.textColor = .gray
        label.font = UIFont.boldSystemFont(ofSize: 13.0)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 2

        spinner.color = .black

        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(spinner)
        stackView.addArrangedSubview(label)

        spinnerBoxView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: spinnerBoxView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: spinnerBoxView.centerYAnchor)
        ])
    }
    
    private func showSpinner() {
        spinner.startAnimating()
        spinnerBoxView.isHidden = false
    }

    private func hideSpinner() {
        spinner.stopAnimating()
        spinnerBoxView.isHidden = true
    }
}

extension ViewController : CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self.locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            showError(error: NSError(domain: "", code: 0,
                                            userInfo: [NSLocalizedDescriptionKey : "Location permissions denied. Go to the app Settings and allow location access."]))
        case .authorizedAlways, .authorizedWhenInUse:
            // Automatically connect to portal, if Location permission is granted
            connectToPortal()
        default:
            return
        }
    }
}

extension ViewController : AGSLocationChangeHandlerDelegate {
    func locationDataSource(_ locationDataSource: AGSLocationDataSource, statusDidChange status: AGSLocationDataSourceStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch status {
            // Is called immediately after user starts ILDS. It takes a while to completely start the ILDS.
            case .starting:
                self.showSpinner()
            // Is called once ILDS successfully started.
            case .started:
                self.startStopButton.setTitle("Stop ILDS", for: .normal)

                self.hideSpinner()
                self.showStartStopButton()
            // Is called if ILDS failed to start. Can happen if user provides a wrong UUID, the positioning table has no entries etc.
            case .failedToStart:
                self.hideSpinner()
                self.showError(error: NSError(domain: "", code: 0,
                                                     userInfo: [NSLocalizedDescriptionKey : "Failed to start ILDS. Error: \(self.ilds?.error?.localizedDescription ?? "")"]))

            // There are 2 ways how the ILDS can be stopped.
            // 1. User normally stops it in case of need.
            // 2. ILDS stops because of some internal error, e.g. user revoked the location permission.
            // In both cases statusDidchange will be triggered. To distinguish both cases we introduced stopping flag, that is set to true once user stops ILDS manually.
            case .stopped:
                self.startStopButton.setTitle("Start ILDS", for: .normal)

                if self.stopping {
                    self.stopping = false
                } else {
                    self.mapView.locationDisplay.stop()
                    self.showError(error: NSError(domain: "", code: 0,
                                                         userInfo: [NSLocalizedDescriptionKey : "ILDS stopped due to an internal error"]))
                }
            case .stopping:
                break

            @unknown default:
                break
            }
        }
    }
    
    func locationDataSource(_ locationDataSource: AGSLocationDataSource, locationDidChange location: AGSLocation) {
        // Handle updated location data and update UI with additional information
    }
}
