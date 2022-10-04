//
//  MockView.swift
//  ExampleStackView
//
//  Created by Görkem Gür on 13.09.2022.
//

import Foundation
import UIKit

public protocol NibLoadable {
    static var nibName: String { get }
}

class MockView: UIView, NibLoadable {
    
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var bottomLine: UIView!
    
    private var mockDataModel: MockExampleModel?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupFromNib()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupFromNib()
    }
    
    func setupView(showBottomLine: Bool,model: MockExampleModel) {
        
        self.mockDataModel = model
        bottomLine.isHidden = !showBottomLine
        self.titleLabel.text = model.title
        self.descriptionLabel.text = model.description
    }
    
    func getModel() -> MockExampleModel? {
        return mockDataModel
    }
    
    func setSelected() {
        self.backgroundColor = .red
        self.setNeedsLayout()
        self.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
            self.backgroundColor = .clear
        })
    }
    
}

//If u are using with xib you need implement that extension and the Nibloadable Protocol top of this class

public extension NibLoadable where Self: UIView {

    static var nibName: String {
        return String(describing: Self.self) // defaults to the name of the class implementing this protocol.
    }

    static var nib: UINib {
        let bundle = Bundle(for: Self.self)
        return UINib(nibName: Self.nibName, bundle: bundle)
    }

    func setupFromNib() {
        guard let view = Self.nib.instantiate(withOwner: self, options: nil).first as? UIView else { fatalError("Error loading \(self) from nib") }
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        view.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor, constant: 0).isActive = true
        view.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
        view.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor, constant: 0).isActive = true
    }
}
