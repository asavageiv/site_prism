# frozen_string_literal: true

require 'spec_helper'

describe SitePrism::Loadable do
  let(:loadable) do
    Class.new do
      include SitePrism::Loadable
    end
  end

  describe '.load_validations' do
    context 'with no inherited classes' do
      it 'returns load_validations from the current class' do
        validation1 = -> { true }
        validation2 = -> { true }

        loadable.load_validation(&validation1)
        loadable.load_validation(&validation2)

        expect(loadable.load_validations).to eq([validation1, validation2])
      end
    end

    context 'with inherited classes' do
      it 'returns load_validations from the current and inherited classes' do
        subklass = Class.new(loadable)
        validation1 = -> { true }
        validation2 = -> { true }
        validation3 = -> { true }
        validation4 = -> { true }

        subklass.load_validation(&validation1)
        loadable.load_validation(&validation2)
        subklass.load_validation(&validation3)
        loadable.load_validation(&validation4)

        expect(subklass.load_validations).to eq(
          [validation2, validation4, validation1, validation3]
        )
      end
    end

    context 'With default validations disabled' do
      before do
        SitePrism.default_load_validations = false
      end

      after do
        # Reset the Default Constructor so its behaviour can be modified
        SitePrism::Page.remove_instance_variable(:@_load_validations)
        SitePrism.default_load_validations = true
      end

      context 'A standard Page' do
        it 'has no default load validations' do
          klass = Class.new(SitePrism::Page)

          expect(klass.load_validations.length).to eq(0)
        end
      end
    end

    context 'With default validations enabled' do
      context 'A standard Page' do
        it 'has 1 default load validation' do
          klass = Class.new(SitePrism::Page)

          expect(klass.load_validations.length).to eq(1)
        end
      end
    end
  end

  describe '.load_validation' do
    it 'adds validations to the load_validations list' do
      expect { loadable.load_validation { true } }
        .to change { loadable.load_validations.size }.by(1)
    end
  end

  describe '#when_loaded' do
    it "executes and yields itself to the provided block \
when all load validations pass" do
      loadable.load_validation { true }
      instance = loadable.new

      expect(instance).to receive(:foo)

      instance.when_loaded(&:foo)
    end

    it 'raises an ArgumentError if no block is given' do
      expect { loadable.new.when_loaded }
        .to raise_error(ArgumentError)
        .with_message('A block was expected, but none received.')
    end

    context 'Failing Validations' do
      it 'raises a NotLoadedError with a default message' do
        james_bond = spy

        loadable.load_validation { true }
        loadable.load_validation { false }

        expect { loadable.new.when_loaded { james_bond.drink_martini } }
          .to raise_error(SitePrism::NotLoadedError)
          .with_message('Failed to load - No reason specified.')

        expect(james_bond).not_to have_received(:drink_martini)
      end

      it 'raises a NotLoadedError with a user-defined message' do
        loadable.load_validation { [false, 'VALIDATION FAILED'] }

        expect { loadable.new.when_loaded { :foo } }
          .to raise_error(SitePrism::NotLoadedError)
          .with_message('Failed to load. Reason: VALIDATION FAILED')
      end
    end

    it 'raises an error immediately on the first validation failure' do
      validation_spy1 = spy(valid?: false)
      validation_spy2 = spy(valid?: false)

      loadable.load_validation { validation_spy1.valid? }
      loadable.load_validation { validation_spy2.valid? }

      expect { loadable.new.when_loaded { puts 'foo' } }
        .to raise_error(SitePrism::NotLoadedError)

      expect(validation_spy1).to have_received(:valid?).once
      expect(validation_spy2).not_to have_received(:valid?)
    end

    it 'executes validations only once for nested calls' do
      james_bond = spy
      validation_spy1 = spy(valid?: true)

      loadable.load_validation { validation_spy1.valid? }
      instance = loadable.new

      instance.when_loaded do
        instance.when_loaded do
          instance.when_loaded do
            james_bond.drink_martini
          end
        end
      end

      expect(james_bond).to have_received(:drink_martini)
      expect(validation_spy1).to have_received(:valid?).once
    end

    it 'resets the loaded cache at the end of the block' do
      loadable.load_validation { true }
      instance = loadable.new

      expect(instance.loaded).to be nil

      instance.when_loaded { |i| expect(i.loaded).to be true }

      expect(instance.loaded).to be nil
    end
  end

  describe '#loaded?' do
    class PageWithUrl < SitePrism::Page
      set_url '/bob'
    end

    # We want to test with multiple inheritance
    let(:inheriting_loadable) { Class.new(loadable) }
    let(:displayed?) { true }

    subject { PageWithUrl.new }

    before do
      allow(subject).to receive(:displayed?).and_return(displayed?)
    end

    it 'returns true if loaded value is cached' do
      validation_spy1 = spy(valid?: true)
      loadable.load_validation { validation_spy1.valid? }
      instance = loadable.new
      instance.loaded = true

      expect(instance).to be_loaded
      expect(validation_spy1).not_to have_received(:valid?)
    end

    it 'returns true if all load validations pass' do
      loadable.load_validation { true }
      loadable.load_validation { true }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { true }

      expect(inheriting_loadable.new).to be_loaded
    end

    it 'returns false if a defined load validation fails' do
      loadable.load_validation { true }
      loadable.load_validation { true }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { false }

      expect(inheriting_loadable.new).not_to be_loaded
    end

    it 'returns false if an inherited load validation fails' do
      loadable.load_validation { true }
      loadable.load_validation { false }
      inheriting_loadable.load_validation { true }
      inheriting_loadable.load_validation { true }

      expect(inheriting_loadable.new).not_to be_loaded
    end

    it 'sets the load_error if a failing load_validation supplies one' do
      loadable.load_validation { [true, 'this cannot fail'] }
      loadable.load_validation { [false, 'fubar'] }
      inheriting_loadable.load_validation { [true, 'this also cannot fail'] }

      instance = inheriting_loadable.new
      instance.loaded?

      expect(instance.load_error).to eq('fubar')
    end

    context 'when page is loaded' do
      it { is_expected.to be_loaded }
    end

    context 'when page is not loaded' do
      let(:displayed?) { false }

      it { is_expected.not_to be_loaded }
    end
  end
end
